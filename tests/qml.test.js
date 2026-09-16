import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, rmSync, symlinkSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Compile-level gate for every shipped QML file. The qmltestrunner suite only
// instantiates DisplayGallery and ArrangementEditor; a syntax or compile error
// in Panel.qml (the actual bar entry point) would otherwise ship green.
// qmllint resolves qs.Ui/qs.Commons against the real installed shell modules
// through a temporary qs/* symlink tree. Warnings (unqualified delegate access,
// singleton member lookups) are informational; only hard errors fail the gate.
const root = fileURLToPath(new URL('..', import.meta.url));
const qmllint = '/usr/lib/qt6/bin/qmllint';
const shellRoot = '/usr/share/omarchy/shell';

test('all shipped QML files compile without errors', t => {
  if (!existsSync(qmllint) || !existsSync(path.join(shellRoot, 'Ui', 'qmldir'))) {
    t.skip('qmllint or the omarchy shell modules are unavailable');
    return;
  }
  const imports = mkdtempSync(path.join(tmpdir(), 'monitor-switcher-qml-'));
  t.after(() => rmSync(imports, { recursive: true, force: true }));
  mkdirSync(path.join(imports, 'qs'));
  symlinkSync(path.join(shellRoot, 'Ui'), path.join(imports, 'qs', 'Ui'));
  symlinkSync(path.join(shellRoot, 'Commons'), path.join(imports, 'qs', 'Commons'));
  const files = readdirSync(root).filter(f => f.endsWith('.qml')).sort();
  assert.ok(files.includes('Panel.qml') && files.includes('DragSlider.qml'), 'shipped QML files found');
  for (const file of files) {
    const result = spawnSync(qmllint, ['-I', imports, path.join(root, file)], { encoding: 'utf8' });
    const output = `${result.stdout || ''}${result.stderr || ''}`;
    assert.ifError(result.error);
    const errors = output.split('\n').filter(line => line.startsWith('Error:'));
    assert.deepEqual(errors, [], `${file}:\n${output}`);
  }
});
