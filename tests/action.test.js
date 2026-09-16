const test = require('node:test')
const assert = require('node:assert/strict')
const {spawn} = require('node:child_process')
const fs = require('node:fs/promises')
const path = require('node:path')
const os = require('node:os')

test('display action finishes after its initiating panel process disappears', async t => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'monitor-action-test-'))
  t.after(() => fs.rm(dir, {recursive: true, force: true}))
  await fs.copyFile(path.join(__dirname, '../bin/monitor-action'), path.join(dir, 'monitor-action'))
  await fs.writeFile(path.join(dir, 'monitor-switcher'), '#!/bin/bash\nprintf started > "$1/started"\nsleep 0.3\nprintf applied > "$1/finished"\nprintf "done\\n"\n', {mode: 0o700})
  const child = spawn('bash', [path.join(dir, 'monitor-action'), dir], {stdio: ['ignore', 'pipe', 'pipe']})
  t.after(() => { if (child.exitCode === null) child.kill() })
  const exited = new Promise(resolve => child.on('exit', resolve))
  for (let i = 0; i < 100; i++) {
    if (await fs.readFile(path.join(dir, 'started')).then(()=>true,()=>false)) break
    await new Promise(resolve => setTimeout(resolve, 20))
  }
  assert.equal(await fs.readFile(path.join(dir, 'started'), 'utf8'), 'started')
  child.kill('SIGKILL')
  child.stdout.destroy(); child.stderr.destroy()
  await exited
  for (let i = 0; i < 100; i++) {
    if (await fs.readFile(path.join(dir, 'finished')).then(()=>true,()=>false)) break
    await new Promise(resolve => setTimeout(resolve, 20))
  }
  assert.equal(await fs.readFile(path.join(dir, 'finished'), 'utf8'), 'applied')
})
