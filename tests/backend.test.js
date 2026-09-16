import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rename, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const backend = fileURLToPath(new URL('../bin/monitor-switcher', import.meta.url));
const advertised = [
  '3840x2160@60.00Hz', '1920x1080@360.00Hz', '3840x2160@240.00Hz',
  '3840x2160@59.94Hz', '3840x2160@239.97Hz', '3840x2160@240.00Hz',
  '3840x2160@120.00', 'garbage', '3840x2160@240.00Hz trailing',
];

// Never delegates to a real hyprctl. Every invocation requires the sandbox marker
// and a small allowlist; all other commands fail closed.
const stub = `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const home = process.env.HOME;
if (!home || !path.basename(home).startsWith('monitor-switcher-test-') ||
    fs.readFileSync(path.join(home, 'SANDBOX'), 'utf8') !== 'no live monitors') process.exit(97);
const args = process.argv.slice(2).join(' ');
fs.appendFileSync(path.join(home, 'calls'), args + '\\n');
const control = JSON.parse(fs.readFileSync(path.join(home, 'control.json'), 'utf8'));
const liveFile = path.join(home, 'live.json');
const lua = path.join(home, '.local/state/omarchy/toggles/hypr/monitor-switcher.lua');
if (args === 'monitors all -j') {
  if (control.failure === 'apply' && fs.existsSync(path.join(home, '.local/state/monitor-switcher/refresh-pending.json'))) {
    console.log('invalid monitor data'); process.exit(0);
  }
  process.stdout.write(fs.readFileSync(liveFile));
} else if (args === 'reload') {
  if (control.failure === 'hang-reload' || control.failure === 'orphan-reload') {
    const { spawn } = require('node:child_process');
    const child = spawn(process.execPath, ['-e', 'process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)'],
      { stdio: ['ignore', 'inherit', 'inherit'] });
    fs.writeFileSync(path.join(home, 'hung-pids.json'), JSON.stringify([process.pid, child.pid]));
    if (control.failure === 'orphan-reload') process.exit(0);
    process.on('SIGTERM', () => {});
    setInterval(() => {}, 1000);
    return;
  }
  const layout = fs.existsSync(lua) ? fs.readFileSync(lua, 'utf8') : null;
  const text = layout ?? '';
  const mode = text.match(/output = "DP-1", mode = "([0-9]+)x([0-9]+)@([0-9.]+)"/);
  const changing = (mode && Number(mode[3]) !== 60) || (control.failGenerated && text.startsWith('-- GENERATED'));
  if ((changing && control.failure === 'reload') || control.failure === 'always-reload') {
    fs.appendFileSync(path.join(home, 'reload-failures'), 'failed\\n');
    console.error('stub reload failure'); process.exit(1);
  }
  if (changing && control.failure === 'rejection') { console.log('error: unsupported mode'); process.exit(0); }
  const live = JSON.parse(fs.readFileSync(liveFile, 'utf8'));
  for (const line of text.split('\\n')) {
    const name = line.match(/output = "([A-Za-z0-9_.-]+)"/);
    const monitor = name && live.find(m => m.name === name[1]);
    if (!monitor) continue;
    if (line.includes('disabled = true')) {
      if (!control.ignorePower) { monitor.disabled = true; monitor.width = monitor.height = 0; }
      continue;
    }
    const m = line.match(/mode = "([0-9]+)x([0-9]+)@([0-9.]+)"/);
    const p = line.match(/position = "(-?[0-9]+)x(-?[0-9]+)"/);
    const s = line.match(/scale = ([0-9.]+)/);
    const t = line.match(/transform = ([0-9]+)/);
    if (m && control.failure !== 'verify') {
      monitor.width = Number(m[1]); monitor.height = Number(m[2]);
      monitor.refreshRate = Number(m[3]) + (monitor.name === 'DP-1' ? control.rateOffset || 0 : 0);
      if (monitor.name === 'DP-1' && text.startsWith('-- GENERATED') && control.liveRate !== undefined) monitor.refreshRate = control.liveRate;
      if (changing && control.failure === 'resolution' && monitor.name === 'DP-1') monitor.width = 1920;
    }
    if (!control.ignorePower) monitor.disabled = false;
    if (p && !control.ignorePosition) { monitor.x = Number(p[1]); monitor.y = Number(p[2]); }
    if (s && !control.ignoreScale) monitor.scale = Number(s[1]);
    if (t) monitor.transform = Number(t[1]);
  }
  fs.writeFileSync(liveFile, JSON.stringify(live));
  fs.appendFileSync(path.join(home, 'applied-layouts'), JSON.stringify(layout) + '\\n');
  console.log('ok');
} else if (args === 'configerrors -j') {
  const text = fs.existsSync(lua) ? fs.readFileSync(lua, 'utf8') : '';
  const changing = text.includes('@240.00') || (control.failGenerated && text.startsWith('-- GENERATED'));
  console.log(JSON.stringify(control.failure === 'configerrors' && changing ? ['stub invalid mode'] : (control.configerrors ?? [])));
} else if (args === 'eval hl.dispatch(hl.dsp.focus({monitor = "DP-1"}))' || args === 'eval hl.dispatch(hl.dsp.focus({monitor = "DP-2"}))') {
  const live = JSON.parse(fs.readFileSync(liveFile, 'utf8'));
  for (const m of live) m.focused = m.name === (args.includes('"DP-1"') ? 'DP-1' : 'DP-2');
  fs.writeFileSync(liveFile, JSON.stringify(live));
  console.log('ok');
} else { console.error('FORBIDDEN hyprctl invocation: ' + args); process.exit(98); }
`;

test('clean configerrors can contain blank entries on Hyprland Lua builds', async t => {
  const f = await fixture(t, { control: { configerrors: ['', '  '] } });
  const result = await f.run('apply');
  assert.equal(result.code, 0, result.stderr);
});

async function waitFor(check, timeout = 6000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.fail('timed out waiting for sandbox condition');
}

async function fixture(t, options = {}) {
  const home = await mkdtemp(path.join(tmpdir(), 'monitor-switcher-test-'));
  const config = path.join(home, '.config/monitor-switcher/config.json');
  const generated = path.join(home, '.local/state/omarchy/toggles/hypr/monitor-switcher.lua');
  const stateDir = path.join(home, '.local/state/monitor-switcher');
  const pending = path.join(stateDir, 'refresh-pending.json');
  const bin = path.join(home, 'bin');
  await Promise.all([mkdir(path.dirname(config), { recursive: true }),
    mkdir(path.dirname(generated), { recursive: true }), mkdir(stateDir, { recursive: true }), mkdir(bin)]);
  const monitors = options.monitors ?? [
    { output: 'DP-1', alias: 'Main', mode: 'preferred', mode_w: 3840, mode_h: 2160,
      scale: 1.5, transform: 1, position: '-1440x100', custom: { keep: true } },
    { output: 'DP-2', alias: 'Side', mode: '1920x1080@60', scale: 1, transform: 0, position: '0x0' },
  ];
  const live = options.live ?? [
    { name: 'DP-1', width: 3840, height: 2160, scale: 1.5, transform: 1,
      x: -1440, y: 100, refreshRate: 60, disabled: false, availableModes: advertised },
    { name: 'DP-2', width: 1920, height: 1080, scale: 1, transform: 0,
      x: 0, y: 0, refreshRate: 60, disabled: false, availableModes: ['1920x1080@60.00Hz'] },
  ];
  const originalConfig = JSON.stringify(monitors, null, 4) + '\n\n';
  const originalLua = '-- previous generated layout\nhl.monitor({ output = "DP-1", mode = "3840x2160@60.00", position = "-1440x100", scale = 1.5, transform = 1 })\n\n';
  await Promise.all([
    writeFile(config, originalConfig), writeFile(generated, originalLua),
    writeFile(path.join(home, 'SANDBOX'), 'no live monitors'),
    writeFile(path.join(home, 'live.json'), JSON.stringify(live)),
    writeFile(path.join(home, 'control.json'), JSON.stringify(options.control ?? {})),
    writeFile(path.join(stateDir, 'state.json'), JSON.stringify({ disabled: options.disabled ?? [] })),
    writeFile(path.join(bin, 'hyprctl'), stub, { mode: 0o700 }),
  ]);
  const env = { HOME: home, PATH: `${bin}:/usr/bin:/bin`, LC_ALL: 'C' };
  const children = new Set();
  function run(...args) {
    return new Promise((resolve, reject) => {
      const child = spawn('/usr/bin/bash', [backend, ...args], { env, stdio: ['ignore', 'pipe', 'pipe'] });
      children.add(child);
      let stdout = '', stderr = '';
      const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error(`command timed out: ${args}`)); }, 30000);
      child.stdout.on('data', data => { stdout += data; });
      child.stderr.on('data', data => { stderr += data; });
      child.on('error', reject);
      child.on('close', (code, signal) => {
        clearTimeout(timer); children.delete(child);
        resolve({ code, signal, stdout, stderr });
      });
    });
  }
  const json = async file => JSON.parse(await readFile(file, 'utf8'));
  const watchdogs = new Set();
  async function rememberWatchdog() {
    try { watchdogs.add((await json(path.join(stateDir, 'refresh-watchdog.json'))).pid); } catch {}
  }
  async function stopWatchdog() {
    const { pid } = await json(path.join(stateDir, 'refresh-watchdog.json'));
    process.kill(-pid, 'SIGKILL');
    watchdogs.delete(pid);
  }
  t.after(async () => {
    for (const child of children) child.kill('SIGKILL');
    await rememberWatchdog();
    for (const pid of watchdogs) {
      // Only the detached session created and acknowledged inside this fixture.
      try { process.kill(-pid, 'SIGKILL'); } catch {}
    }
    for (const pid of await json(path.join(home, 'hung-pids.json')).catch(() => [])) {
      try { process.kill(pid, 'SIGKILL'); } catch {}
    }
    await rm(home, { recursive: true, force: true });
  });
  return { home, config, generated, stateDir, pending, bin, env, run, json, rememberWatchdog, stopWatchdog,
    originalConfig, originalLua, monitors, live,
    async ok(...args) { const result = await run(...args); assert.equal(result.code, 0, result.stderr); return result; },
    async unchanged() {
      assert.equal(await readFile(config, 'utf8'), originalConfig);
      assert.equal(await readFile(generated, 'utf8'), originalLua);
    },
    async noPending() { await assert.rejects(readFile(pending), { code: 'ENOENT' }); },
    async control(value) {
      await writeFile(path.join(home, 'control.tmp'), JSON.stringify(value));
      await rename(path.join(home, 'control.tmp'), path.join(home, 'control.json'));
    },
    async setPending(value) {
      await writeFile(`${pending}.tmp`, JSON.stringify(value));
      await rename(`${pending}.tmp`, pending);
    },
  };
}

test('state advertises sorted unique rates at configured resolution, not transient live resolution/Hz', async t => {
  const f = await fixture(t);
  f.live[0].width = 1920;
  f.live[0].height = 1080;
  f.live[0].refreshRate = 239.999;
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  const m = state.monitors[0];
  assert.equal(state.refreshPending, null);
  assert.equal(m.configuredWidth, 3840);
  assert.equal(m.configuredHeight, 2160);
  assert.equal(m.transform, 1);
  assert.equal(m.refreshRate, 239.999);
  assert.deepEqual(m.refreshModes, [
    { mode: '3840x2160@59.94', rate: 59.94 }, { mode: '3840x2160@60.00', rate: 60 },
    { mode: '3840x2160@120.00', rate: 120 }, { mode: '3840x2160@239.97', rate: 239.97 },
    { mode: '3840x2160@240.00', rate: 240 },
  ]);
});

test('disabled zero geometry and unplugged monitors retain configured dimensions and null refresh', async t => {
  const f = await fixture(t);
  f.live[0] = { ...f.live[0], width: 0, height: 0, disabled: true, refreshRate: 0 };
  f.monitors.push({ output: 'DP-3', mode: '2560x1440@144', scale: 1, transform: 3 });
  await writeFile(f.config, JSON.stringify(f.monitors));
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const { monitors } = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(monitors[0].width, 0);
  assert.equal(monitors[0].configuredWidth, 3840);
  assert.equal(monitors[0].refreshRate, null);
  assert.equal(monitors[0].refreshModes.length, 5);
  assert.equal(monitors[2].configuredWidth, 2560);
  assert.equal(monitors[2].configuredHeight, 1440);
  assert.equal(monitors[2].refreshRate, null);
  assert.deepEqual(monitors[2].refreshModes, []);
});

test('exact 240 mode persists, drops snapshots and preserves settings; confirm keeps both files', async t => {
  const f = await fixture(t, { control: { rateOffset: -0.001 } });
  const started = Date.now() / 1000;
  const result = await f.ok('refresh', 'main', '240');
  assert.match(result.stdout, /3840x2160@240.00 pending/);
  const pending = await f.json(f.pending);
  assert.match(pending.token, /^[a-f0-9]{32}$/);
  assert.ok(pending.expiresAt >= started + 19);
  assert.ok(pending.expiresAt > Date.now() / 1000 + 13);
  assert.equal(pending.config, f.originalConfig);
  assert.equal(pending.generated, f.originalLua);
  const cfg = await f.json(f.config);
  const { mode_w, mode_h, ...expected } = f.monitors[0];
  assert.deepEqual(cfg[0], { ...expected, mode: '3840x2160@240.00' });
  assert.deepEqual(cfg[1], f.monitors[1]);
  const lua = await readFile(f.generated, 'utf8');
  assert.match(lua, /mode = "3840x2160@240.00", position = "-1440x100", scale = 1.5, transform = 1/);
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.deepEqual(state.refreshPending, { token: pending.token, output: 'DP-1', mode: pending.mode, expiresAt: pending.expiresAt, reverting: false });
  assert.match((await f.ok('confirm', pending.token)).stdout, /confirmed/);
  await f.noPending();
  assert.deepEqual(await f.json(f.config), cfg);
  assert.equal(await readFile(f.generated, 'utf8'), lua);
});

test('fractional selection is exact and explicit revert restores both files byte for byte', async t => {
  const f = await fixture(t);
  await f.ok('refresh', '1', '239.97');
  const pending = await f.json(f.pending);
  assert.equal(pending.mode, '3840x2160@239.97');
  await f.ok('revert', pending.token);
  await f.unchanged();
  await f.noPending();
});

test('invalid rates, unsupported rates, unknown and nonactive IDs are rejected without writes', async t => {
  const f = await fixture(t);
  for (const rate of ['', 'NaN', 'Infinity', '-1', '0', '240Hz', '2.4e2', '240;true', '239.98', '360', '999999999999999999999999']) {
    assert.notEqual((await f.run('refresh', 'DP-1', rate)).code, 0, rate);
    await f.unchanged();
    await f.noPending();
  }
  for (const id of ['missing', '0', '99']) assert.match((await f.run('refresh', id, '240')).stderr, /unknown monitor/);
  await writeFile(path.join(f.stateDir, 'state.json'), JSON.stringify({ disabled: ['DP-1'] }));
  assert.match((await f.run('refresh', 'DP-1', '240')).stderr, /connected and active/);
  await writeFile(path.join(f.stateDir, 'state.json'), JSON.stringify({ disabled: [] }));
  f.live[0].disabled = true;
  f.live[0].width = f.live[0].height = 0;
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  assert.match((await f.run('refresh', 'DP-1', '240')).stderr, /connected and active/);
  f.live.shift();
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  assert.match((await f.run('refresh', 'DP-1', '240')).stderr, /connected and active/);
  await f.unchanged();
  assert.doesNotMatch(await readFile(path.join(f.home, 'calls'), 'utf8'), /reload/);
});

for (const failure of ['apply', 'rejection', 'reload', 'configerrors', 'verify', 'resolution']) {
  test(`${failure} failure restores config AND Lua and clears pending`, async t => {
    const f = await fixture(t, { control: { failure } });
    const result = await f.run('refresh', 'DP-1', '240');
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /refresh failed; restoring/);
    await f.unchanged();
    await f.noPending();
    assert.equal((await f.json(path.join(f.home, 'live.json')))[0].refreshRate, 60);
  });
}

test('verification distinguishes 59.94 from 60 despite small precision tolerance', async t => {
  const f = await fixture(t, { control: { failure: 'verify' } });
  const result = await f.run('refresh', 'DP-1', '59.94');
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /verification failed/);
  await f.unchanged();
  await f.noPending();
});

test('verification cannot mistake the adjacent 239.97 mode for 240', async t => {
  const f = await fixture(t, { control: { rateOffset: -0.03 } });
  const result = await f.run('refresh', 'DP-1', '240');
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /verification failed/);
  await f.unchanged();
  await f.noPending();
});

for (const [rate, liveRate, accepted] of [
  [59.99, 60, false], [60, 59.99, false], [60, 59.994, false],
  [60, 59.997, true], [74.98, 74.977, true], [74.97, 74.977, false],
]) {
  test(`two-decimal verification: requested ${rate}, live ${liveRate}, accepted ${accepted}`, async t => {
    const f = await fixture(t, { control: { liveRate } });
    f.live[0].availableModes = [...advertised, '3840x2160@59.99Hz', '3840x2160@74.97Hz', '3840x2160@74.98Hz'];
    await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
    const result = await f.run('refresh', 'DP-1', String(rate));
    if (accepted) {
      assert.equal(result.code, 0, result.stderr);
      const pending = await f.json(f.pending);
      assert.equal(pending.mode, `3840x2160@${rate.toFixed(2)}`);
      await f.ok('revert', pending.token);
    } else {
      assert.notEqual(result.code, 0);
      assert.match(result.stderr, /verification failed/);
    }
    await f.unchanged();
    await f.noPending();
  });
}

test('watchdog launch failure refuses the change and restores backups', async t => {
  const f = await fixture(t);
  await writeFile(path.join(f.bin, 'setsid'), '#!/usr/bin/bash\nexit 1\n', { mode: 0o700 });
  const result = await f.run('refresh', 'DP-1', '240');
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /could not launch.*watchdog/);
  await f.unchanged();
  await f.noPending();
});

test('rollback reload failure retains the transaction and refuses confirm while reverting', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  await f.control({ failure: 'always-reload' });
  const result = await f.run('revert', pending.token);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /previous files restored, but rollback reload failed/);
  await f.unchanged();
  assert.equal((await f.json(f.pending)).reverting, true);
  assert.equal((await f.json(path.join(f.home, 'live.json')))[0].refreshRate, 240);
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.refreshPending.token, pending.token);
  assert.equal(state.refreshPending.reverting, true);
  assert.match((await f.run('confirm', pending.token)).stderr, /confirmation refused/);
  assert.equal((await f.json(f.pending)).token, pending.token);
  assert.match((await f.run('refresh', 'DP-1', '120')).stderr, /display change pending/);
  // With no worker, confirm must recover but must never keep a reverting change.
  await f.stopWatchdog();
  await f.control({});
  assert.match((await f.run('confirm', pending.token)).stderr, /confirmation refused/);
  await f.unchanged();
  await f.noPending();
});

for (const failure of ['hang-reload', 'orphan-reload']) {
  test(`ordinary apply bounds ${failure}, kills children and releases the lock for state`, async t => {
    const f = await fixture(t, { control: { failure } });
    const begin = Date.now();
    const applying = f.run('apply');
    const pidsFile = path.join(f.home, 'hung-pids.json');
    await waitFor(() => f.json(pidsFile).then(() => true, () => false));
    const firstPids = await f.json(pidsFile);
    const reading = f.run('state', '--json');
    const [result, state] = await Promise.all([applying, reading]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /reload failed or timed out/);
    assert.equal(state.code, 0, state.stderr);
    assert.equal(JSON.parse(state.stdout).refreshPending, null);
    assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
    assert.equal((await readFile(path.join(f.home, 'calls'), 'utf8')).split('\n').filter(call => call === 'reload').length, 2);
    assert.ok(Date.now() - begin < 8000, 'a reload or inherited pipe/lock must not hang');
    for (const pid of [...firstPids, ...await f.json(pidsFile)]) {
      await waitFor(async () => {
        const stat = await readFile(`/proc/${pid}/stat`, 'utf8').catch(() => null);
        return stat === null || stat.includes(') Z ');
      });
    }
  });
}

test('pending state is read-only; all concurrent modifiers including plan are refused', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const beforeConfig = await readFile(f.config, 'utf8');
  const beforeLua = await readFile(f.generated, 'utf8');
  const beforePending = await readFile(f.pending, 'utf8');
  f.live.push({ name: 'NEW', width: 800, height: 600, disabled: false, scale: 1 });
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const commands = [['refresh', 'DP-1', '120'], ['scale', 'DP-1', '2'], ['toggle', 'DP-2'],
    ['enable', 'DP-2'], ['disable', 'DP-2'], ['move', 'DP-2', '3000x0'], ['swap', '1', '2'],
    ['pack'], ['apply'], ['plan', '--json']];
  const results = await Promise.all(commands.map(args => f.run(...args)));
  for (const result of results) { assert.equal(result.code, 75); assert.match(result.stderr, /display change pending/); }
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.monitors.length, 2);
  assert.equal(await readFile(f.config, 'utf8'), beforeConfig);
  assert.equal(await readFile(f.generated, 'utf8'), beforeLua);
  assert.equal(await readFile(f.pending, 'utf8'), beforePending);
  await f.ok('revert', state.refreshPending.token);
});

test('concurrent refresh requests serialize and only one can create a transaction', async t => {
  const f = await fixture(t);
  const results = await Promise.all([f.run('refresh', 'DP-1', '240'), f.run('refresh', 'DP-1', '120')]);
  assert.equal(results.filter(r => r.code === 0).length, 1);
  assert.match(results.find(r => r.code !== 0).stderr, /display change pending/);
  const pending = await f.json(f.pending);
  assert.equal(pending.config, f.originalConfig);
  await f.ok('revert', pending.token);
  await f.unchanged();
});

test('concurrent confirm/revert serialize and exactly one finalizes the transaction', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  const results = await Promise.all([f.run('confirm', pending.token), f.run('revert', pending.token)]);
  assert.equal(results.filter(r => r.code === 0).length, 1);
  await f.noPending();
  if (results[0].code === 0) assert.equal((await f.json(f.config))[0].mode, '3840x2160@240.00');
  else await f.unchanged();
});

test('invalid/stale tokens and an old worker cannot affect a later transaction', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const first = await f.json(f.pending);
  await f.rememberWatchdog();
  for (const token of ['../../config', 'x', '0'.repeat(32)]) {
    for (const command of ['confirm', 'revert']) assert.notEqual((await f.run(command, token)).code, 0);
  }
  assert.equal((await f.json(f.pending)).token, first.token);
  await f.ok('confirm', first.token);
  assert.notEqual((await f.run('confirm', first.token)).code, 0);
  await f.ok('refresh', 'DP-1', '120');
  const second = await f.json(f.pending);
  assert.notEqual(first.token, second.token);
  assert.notEqual((await f.run('revert', first.token)).code, 0);
  assert.notEqual((await f.run('_refresh-watchdog', first.token)).code, 0);
  assert.equal((await f.json(f.pending)).token, second.token);
  assert.equal((await f.json(f.config))[0].mode, '3840x2160@120.00');
  await f.ok('revert', second.token);
  assert.equal((await f.json(f.config))[0].mode, '3840x2160@240.00');
});

test('expired watchdog worker restores both files; confirm cannot keep an expired change', async t => {
  const f = await fixture(t);
  for (const command of ['_refresh-watchdog', 'confirm']) {
    await f.ok('refresh', 'DP-1', '240');
    await f.stopWatchdog();
    const pending = await f.json(f.pending);
    pending.expiresAt = Math.floor(Date.now() / 1000) - 1;
    await f.setPending(pending);
    const result = await f.run(command, pending.token);
    assert.equal(result.code, command === 'confirm' ? 76 : 0, result.stderr);
    await f.unchanged();
    await f.noPending();
  }
});

test('real watchdog retains failed rollback and retries successfully without further commands', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  await f.control({ failure: 'always-reload' });
  await f.setPending({ ...pending, expiresAt: Math.floor(Date.now() / 1000) - 1 });
  // Only observe files here: state/confirm/revert would trigger entry-time recovery.
  await waitFor(async () => {
    const failures = await readFile(path.join(f.home, 'reload-failures'), 'utf8').catch(() => '');
    return failures.trim().split('\n').length >= 2;
  });
  assert.equal((await f.json(f.pending)).reverting, true);
  assert.equal((await f.json(path.join(f.home, 'live.json')))[0].refreshRate, 240);
  await f.unchanged();
  await f.control({});
  await waitFor(() => readFile(f.pending).then(() => false, error => error.code === 'ENOENT'));
  await f.unchanged();
  assert.equal((await f.json(path.join(f.home, 'live.json')))[0].refreshRate, 60);
  await f.rememberWatchdog();
  await f.ok('refresh', 'DP-1', '120');
  const next = await f.json(f.pending);
  assert.notEqual(next.token, pending.token);
  await new Promise(resolve => setTimeout(resolve, 1500));
  assert.equal((await f.json(f.pending)).token, next.token);
  assert.equal((await f.json(f.config))[0].mode, '3840x2160@120.00');
  await f.ok('confirm', next.token);
});

for (const phase of ['expired', 'reverting']) {
  test(`state recovers ${phase} transaction after worker loss and preserves both backups`, async t => {
    const f = await fixture(t);
    await f.ok('refresh', 'DP-1', '240');
    const pending = await f.json(f.pending);
    await f.stopWatchdog();
    await f.control({ failure: 'always-reload' });
    if (phase === 'expired') {
      await f.setPending({ ...pending, expiresAt: Math.floor(Date.now() / 1000) - 1 });
    } else {
      assert.notEqual((await f.run('revert', pending.token)).code, 0);
      assert.equal((await f.json(f.pending)).reverting, true);
      assert.ok(pending.expiresAt > Date.now() / 1000);
    }
    const retrying = JSON.parse((await f.ok('state', '--json')).stdout);
    assert.equal(retrying.refreshPending.reverting, true);
    assert.equal(retrying.monitors[0].refreshRate, 240);
    await f.unchanged();
    await f.control({});
    const state = JSON.parse((await f.ok('state', '--json')).stdout);
    assert.equal(state.refreshPending, null);
    assert.equal(state.monitors[0].refreshRate, 60);
    await f.unchanged();
    await f.noPending();
    await f.ok('refresh', 'DP-1', '120');
    const next = await f.json(f.pending);
    assert.notEqual(next.token, pending.token);
    assert.notEqual((await f.run('_refresh-watchdog', pending.token)).code, 0);
    assert.equal((await f.json(f.pending)).token, next.token);
    await f.ok('revert', next.token);
  });
}

test('concurrent recovery rolls back once and an old watchdog cannot revert the next token', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  await f.rememberWatchdog();
  await f.setPending({ ...pending, expiresAt: Math.floor(Date.now() / 1000) - 1 });
  const results = await Promise.all([
    f.run('state', '--json'), f.run('state', '--json'), f.run('confirm', pending.token),
  ]);
  for (const result of results.slice(0, 2)) {
    assert.equal(result.code, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).refreshPending, null);
  }
  assert.notEqual(results[2].code, 0);
  const reloads = async () => (await readFile(path.join(f.home, 'calls'), 'utf8')).split('\n').filter(call => call === 'reload').length;
  assert.equal(await reloads(), 2, 'one apply and exactly one rollback');
  assert.deepEqual(await f.json(f.config), f.monitors);
  assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
  await f.ok('refresh', 'DP-1', '120');
  const next = await f.json(f.pending);
  await new Promise(resolve => setTimeout(resolve, 1500));
  assert.equal((await f.json(f.pending)).token, next.token);
  assert.equal((await f.json(f.config))[0].mode, '3840x2160@120.00');
  assert.equal(await reloads(), 3);
  await f.ok('confirm', next.token);
});

test('detached watchdog survives launcher exit, closes lock/stdio, and reverts at the deadline', async t => {
  const f = await fixture(t);
  const begin = Date.now();
  await f.ok('refresh', 'DP-1', '240');
  assert.ok(Date.now() - begin < 15000, 'launcher must not wait for watchdog output/lock');
  const { pid } = await f.json(path.join(f.stateDir, 'refresh-watchdog.json'));
  const { readlink, readdir } = await import('node:fs/promises');
  for (const fd of ['0', '1', '2']) assert.equal(await readlink(`/proc/${pid}/fd/${fd}`), '/dev/null');
  // Polling briefly acquires a new lock, but no inherited lock may survive sleep.
  await waitFor(async () => {
    const targets = await Promise.all((await readdir(`/proc/${pid}/fd`))
      .map(fd => readlink(`/proc/${pid}/fd/${fd}`).catch(() => '')));
    return !targets.includes(path.join(f.stateDir, 'lock'));
  });
  const pending = await f.json(f.pending);
  const deadline = pending.expiresAt * 1000 + 5000;
  while (Date.now() < deadline) {
    try { await readFile(f.pending); } catch (error) { if (error.code === 'ENOENT') break; throw error; }
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  await f.noPending();
  assert.ok(Date.now() >= pending.expiresAt * 1000, 'must not expire early');
  await f.unchanged();
});

test('rollback removes generated Lua if no previous file existed', async t => {
  const f = await fixture(t);
  await rm(f.generated);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  assert.equal(pending.generated, null);
  await f.ok('revert', pending.token);
  assert.equal(await readFile(f.config, 'utf8'), f.originalConfig);
  await assert.rejects(readFile(f.generated), { code: 'ENOENT' });
  await f.noPending();
});

test('unsafe config, generated, pending and lock paths fail closed', async t => {
  for (const target of ['config', 'generated', 'pending', 'lock', 'ancestor']) {
    const f = await fixture(t);
    const decoy = path.join(f.home, 'decoy');
    await writeFile(decoy, 'do not touch');
    const file = target === 'lock' ? path.join(f.stateDir, 'lock')
      : target === 'ancestor' ? path.dirname(f.generated) : f[target];
    await rm(file, { recursive: true, force: true });
    await symlink(target === 'ancestor' ? f.home : decoy, file);
    const result = await f.run('refresh', 'DP-1', '240');
    assert.notEqual(result.code, 0, target);
    assert.equal(await readFile(decoy, 'utf8'), 'do not touch');
  }
});

test('baseline scale rounding and overlap refusal still work', async t => {
  const f = await fixture(t);
  await f.ok('scale', 'Main', '1.61');
  assert.equal((await f.json(f.config))[0].scale, 1.66667);
  const before = await f.json(f.config);
  const lua = await readFile(f.generated, 'utf8');
  const applied = await readFile(path.join(f.home, 'applied-layouts'), 'utf8');
  const result = await f.run('move', 'DP-2', '-1000x100');
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /overlap/);
  assert.deepEqual(await f.json(f.config), before);
  assert.equal(await readFile(f.generated, 'utf8'), lua);
  assert.equal(await readFile(path.join(f.home, 'applied-layouts'), 'utf8'), applied);
  const boxes = JSON.parse((await f.ok('plan', '--json')).stdout);
  assert.equal(boxes[0].w, 1296);
  assert.equal(boxes[0].h, 2304);
});

for (const command of [['scale', 'DP-1', '2'], ['toggle', 'DP-1']]) {
  for (const failure of ['reload', 'configerrors']) {
    for (const missing of [false, true]) {
      test(`ordinary ${command[0]} ${failure} failure restores config/state and ${missing ? 'absent' : 'previous'} Lua`, async t => {
        const f = await fixture(t, { control: { failure, failGenerated: true } });
        if (missing) await rm(f.generated);
        const result = await f.run(...command);
        assert.notEqual(result.code, 0);
        assert.match(result.stderr, failure === 'reload' ? /reload failed/ : /compositor configerrors/);
        assert.match(result.stderr, command[0] === 'scale' ? /scale reverted/ : /toggle failed/);
        assert.deepEqual(await f.json(f.config), f.monitors);
        assert.deepEqual(await f.json(path.join(f.stateDir, 'state.json')), { disabled: [] });
        if (missing) await assert.rejects(readFile(f.generated), { code: 'ENOENT' });
        else assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
        const calls = (await readFile(path.join(f.home, 'calls'), 'utf8')).trim().split('\n')
          .filter(call => call !== 'monitors all -j');
        assert.deepEqual(calls, failure === 'reload'
          ? ['reload', 'reload', 'configerrors -j']
          : ['reload', 'configerrors -j', 'reload', 'configerrors -j']);
        const applied = (await readFile(path.join(f.home, 'applied-layouts'), 'utf8')).trim().split('\n').map(JSON.parse);
        assert.equal(applied.length, failure === 'reload' ? 1 : 2);
        if (failure === 'configerrors') {
          assert.match(applied[0], command[0] === 'scale'
            ? /output = "DP-1".*scale = 2/ : /output = "DP-1", disabled = true/);
        }
        assert.equal(applied.at(-1), missing ? null : f.originalLua, 'rollback must reload the original layout');
        await f.noPending();
      });
    }
  }
}

test('ordinary apply refuses unsafe or oversized generated backups without writing or reloading', async t => {
  for (const target of ['symlink', 'ancestor', 'oversized']) {
    const f = await fixture(t);
    if (target === 'oversized') {
      await writeFile(f.generated, ' '.repeat(1048577));
    } else if (target === 'symlink') {
      const decoy = path.join(f.home, 'decoy');
      await rename(f.generated, decoy);
      await symlink(decoy, f.generated);
    } else {
      const dir = path.dirname(f.generated);
      const decoy = path.join(f.home, 'decoy');
      await rename(dir, decoy);
      await symlink(decoy, dir);
    }
    const before = await readFile(f.generated, 'utf8');
    const result = await f.run('scale', 'DP-1', '2');
    assert.notEqual(result.code, 0, target);
    assert.deepEqual(await f.json(f.config), f.monitors);
    assert.deepEqual(await f.json(path.join(f.stateDir, 'state.json')), { disabled: [] });
    assert.equal(await readFile(f.generated, 'utf8'), before);
    assert.doesNotMatch(await readFile(path.join(f.home, 'calls'), 'utf8'), /reload/);
    await f.noPending();
  }
});

test('refresh refuses an overlapping layout before creating a transaction or changing files', async t => {
  const f = await fixture(t);
  f.monitors[1].position = '-1000x100';
  const config = JSON.stringify(f.monitors);
  await writeFile(f.config, config);
  const result = await f.run('refresh', 'DP-1', '240');
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /overlap/);
  assert.equal(await readFile(f.config, 'utf8'), config);
  assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
  await f.noPending();
});

test('malformed and oversized pending transactions fail closed, including state', async t => {
  const f = await fixture(t);
  for (const content of ['not JSON', '{}', ' '.repeat(1048576) + '{}']) {
    await writeFile(f.pending, content);
    for (const args of [['state', '--json'], ['apply'], ['confirm', '0'.repeat(32)]]) {
      assert.notEqual((await f.run(...args)).code, 0);
    }
    await f.unchanged();
  }
});

test('an enabled modeless display stays visible and can be recovered without losing the healthy display', async t => {
  const f = await fixture(t);
  f.live[1] = { ...f.live[1], width: 0, height: 0, scale: 1, dpmsStatus: true };
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.monitors.length, 2);
  assert.equal(state.enabledCount, 1);
  assert.equal(state.monitors[1].status, 'No active mode');
  assert.equal(state.monitors[1].enabled, true);
  assert.equal(state.monitors[1].usable, false);
  assert.equal(state.monitors[1].scale, null);
  assert.equal(state.monitors[1].refreshRate, null);
  assert.equal(state.monitors[1].configuredWidth, 1920);
  assert.match((await f.run('disable', 'DP-1')).stderr, /last active display/);
  assert.match((await f.run('focus', 'DP-2')).stderr, /no usable desktop/);
  await f.ok('apply');
  const recovered = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(recovered.enabledCount, 2);
  assert.equal(recovered.monitors[1].width, 1920);
  await f.ok('focus', 'DP-2');
  assert.equal((await f.json(path.join(f.home, 'live.json')))[1].focused, true);
});

test('modeless output can be disabled; externally disabled output toggles on', async t => {
  const f = await fixture(t);
  f.live[1].width = f.live[1].height = 0;
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  await f.ok('disable', 'DP-2');
  assert.deepEqual((await f.json(path.join(f.stateDir, 'state.json'))).disabled, ['DP-2']);
  await writeFile(path.join(f.stateDir, 'state.json'), JSON.stringify({ disabled: [] }));
  await f.ok('toggle', 'DP-2');
  assert.equal((await f.json(path.join(f.home, 'live.json')))[1].disabled, false);
});

test('duplicate outputs fail clearly without multiplying metadata or writing rules', async t => {
  const f = await fixture(t);
  const config = JSON.stringify([...f.monitors, { ...f.monitors[1], alias: 'Duplicate' }]);
  await writeFile(f.config, config);
  for (const command of [['state', '--json'], ['enable', 'DP-2'], ['apply']]) {
    assert.match((await f.run(...command)).stderr, /duplicate monitor outputs: DP-2/);
    assert.equal(await readFile(f.config, 'utf8'), config);
    assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
  }
});

test('hardware reconnection preserves order, settings and off-state; FALLBACK is not adopted', async t => {
  const f = await fixture(t, { disabled: ['DP-2'] });
  const identity = { make: 'Acer', model: 'PE270K', serial: 'unique-serial' };
  f.monitors[1].identity = identity;
  await writeFile(f.config, JSON.stringify(f.monitors));
  f.live[1] = { ...f.live[1], ...identity, name: 'HDMI-A-1', disabled: true, width: 0, height: 0 };
  f.live.push({ name: 'FALLBACK', width: 1920, height: 1080, scale: 1 });
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.monitors.length, 2);
  assert.equal(state.monitors[1].num, 2);
  assert.equal(state.monitors[1].output, 'HDMI-A-1');
  assert.equal(state.monitors[1].alias, 'Side');
  assert.deepEqual((await f.json(path.join(f.stateDir, 'state.json'))).disabled, ['HDMI-A-1']);
  assert.equal((await f.json(f.config))[1].previousOutput, undefined);
});

test('disabled newly discovered monitor gets advertised geometry rather than a zero snapshot', async t => {
  const f = await fixture(t);
  f.live.push({ name: 'HDMI-A-1', disabled: true, width: 0, height: 0, scale: 1,
    availableModes: ['2560x1440@59.95Hz'] });
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.monitors[2].configuredWidth, 2560);
  assert.equal(state.monitors[2].configuredHeight, 1440);
});

test('live scale and configured scale are reported separately', async t => {
  const f = await fixture(t);
  f.live[0].scale = 2;
  await writeFile(path.join(f.home, 'live.json'), JSON.stringify(f.live));
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.monitors[0].scale, 2);
  assert.equal(state.monitors[0].configuredScale, 1.5);
});

for (const [verb, target, disabled] of [['enable', 'DP-2', []], ['disable', 'DP-2', ['DP-2']]]) {
  test(`failed redundant ${verb} restores exact previous power intent`, async t => {
    const f = await fixture(t, { disabled, control: { failure: 'reload', failGenerated: true } });
    assert.notEqual((await f.run(verb, target)).code, 0);
    assert.deepEqual((await f.json(path.join(f.stateDir, 'state.json'))).disabled, disabled);
  });
}

for (const [control, command] of [[{ ignoreScale: true }, ['scale', 'Main', '2']],
  [{ ignorePower: true }, ['disable', 'DP-2']], [{ ignorePosition: true }, ['move', 'DP-2', '2000x0']]]) {
  test(`accepted reload must actually apply ${command[0]}`, async t => {
    const f = await fixture(t, { control });
    assert.match((await f.run(...command)).stderr, /verification failed/);
    assert.deepEqual(await f.json(f.config), f.monitors);
    assert.equal(await readFile(f.generated, 'utf8'), f.originalLua);
    assert.deepEqual((await f.json(path.join(f.stateDir, 'state.json'))).disabled, []);
  });
}

test('resolution and scale trials use exact advertised modes and the shared rollback watchdog', async t => {
  const f = await fixture(t);
  await f.ok('mode', 'Main', '1920x1080@360.00');
  let pending = await f.json(f.pending);
  assert.equal((await f.json(f.config))[0].mode, '1920x1080@360.00');
  await f.ok('revert', pending.token);
  await f.unchanged();
  await f.ok('scale-trial', 'Main', '1.875');
  pending = await f.json(f.pending);
  assert.equal((await f.json(f.config))[0].scale, 1.875);
  await f.ok('revert', pending.token);
  await f.unchanged();
  assert.match((await f.run('mode', 'Main', '640x480@999')).stderr, /not an advertised mode/);
});

test('arrangement swaps every active display atomically, verifies positions and can revert byte for byte', async t => {
  const f = await fixture(t);
  const positions = [{ output: 'DP-1', x: 1920, y: 0 }, { output: 'DP-2', x: 0, y: 0 }];
  await f.ok('arrange', JSON.stringify(positions));
  const pending = await f.json(f.pending);
  assert.equal(pending.mode, 'arrangement');
  const state = JSON.parse((await f.ok('state', '--json')).stdout);
  assert.equal(state.refreshPending.kind, 'arrangement');
  assert.equal(state.monitors[0].x, 1920);
  assert.equal(state.monitors[1].x, 0);
  const cfg = await f.json(f.config);
  assert.equal(cfg[0].position, '1920x0');
  assert.equal(cfg[0].scale, f.monitors[0].scale);
  assert.equal(cfg[0].transform, f.monitors[0].transform);
  await f.ok('revert', pending.token);
  await f.unchanged();
});

test('arrangement rejects overlaps, disconnected islands, corner-only contact, stale displays and malformed positions', async t => {
  const f = await fixture(t);
  for (const positions of [[], [{ output: 'DP-1', x: 0, y: 0 }],
    [{ output: 'DP-1', x: 0, y: 0 }, { output: 'DP-1', x: 1440, y: 0 }],
    [{ output: 'DP-1', x: 0, y: 0 }, { output: 'MISSING', x: 1440, y: 0 }],
    [{ output: 'DP-1', x: 0.5, y: 0 }, { output: 'DP-2', x: 1440, y: 0 }],
    [{ output: 'DP-1', x: 0, y: 0 }, { output: 'DP-2', x: 1000, y: 0 }],
    [{ output: 'DP-1', x: 0, y: 0 }, { output: 'DP-2', x: 3000, y: 0 }],
    [{ output: 'DP-1', x: 0, y: 0 }, { output: 'DP-2', x: 1440, y: 2560 }],
  ]) {
    assert.notEqual((await f.run('arrange', JSON.stringify(positions))).code, 0);
    await f.unchanged();
    await f.noPending();
  }
  assert.doesNotMatch(await readFile(path.join(f.home, 'calls'), 'utf8'), /reload/);
});

test('arrangement rejects accepted-but-ineffective compositor positioning and restores the layout', async t => {
  const f = await fixture(t, { control: { ignorePosition: true } });
  const result = await f.run('arrange', JSON.stringify([{ output: 'DP-1', x: 1920, y: 0 }, { output: 'DP-2', x: 0, y: 0 }]));
  assert.match(result.stderr, /verification failed/);
  await f.unchanged();
  await f.noPending();
});

test('pending trials permit focus without changing settings and report conflicts with a distinct status', async t => {
  const f = await fixture(t);
  await f.ok('refresh', 'DP-1', '240');
  const pending = await f.json(f.pending);
  const config = await readFile(f.config, 'utf8');
  const lua = await readFile(f.generated, 'utf8');
  await f.ok('focus', 'DP-2');
  assert.equal((await f.json(path.join(f.home, 'live.json')))[1].focused, true);
  assert.equal(await readFile(f.config, 'utf8'), config);
  assert.equal(await readFile(f.generated, 'utf8'), lua);
  assert.equal((await f.run('disable', 'DP-2')).code, 75);
  assert.equal((await f.json(f.pending)).token, pending.token);
  await f.ok('revert', pending.token);
  assert.equal((await f.run('confirm', pending.token)).code, 77);
  assert.equal((await f.run('revert', pending.token)).code, 77);
  await f.unchanged();
});

test('first-run diagnostics stay on stderr and state stdout remains valid JSON', async t => {
  const f = await fixture(t);
  await rm(f.config);
  const result = await f.ok('state', '--json');
  assert.match(result.stderr, /created/);
  const state = JSON.parse(result.stdout);
  assert.equal(state.monitors.length, 2);
  assert.equal(state.refreshPending, null);
});
