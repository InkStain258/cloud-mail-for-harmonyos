const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/components/VerificationCodeCard.ets'), 'utf8');

test('verification copy and UI updates are guarded by component lifecycle', () => {
  assert.match(source, /aboutToDisappear\(\): void\s*\{\s*this\.active = false/);
  assert.match(source, /if \(!this\.active \|\| this\.copying/);
  assert.match(source, /finally\s*\{\s*if \(this\.active\) \{ this\.copying = false \}/);
});

test('both clipboard success and failure use a protected awaited toast', () => {
  assert.equal((source.match(/\.openToast\(/g) || []).length, 1);
  assert.match(source, /async showToast[\s\S]*?if \(!this\.active\)[\s\S]*?try\s*\{\s*await this\.getUIContext\(\)\.getPromptAction\(\)\.openToast[\s\S]*?catch/);
  assert.match(source, /await this\.showToast\(\$r\('app\.string\.verification_code_copied'\)\)/);
  assert.match(source, /await this\.showToast\(\$r\('app\.string\.verification_code_copy_failed'\)\)/);
});

test('verification clipboard remains local and native click handlers do not call DOM APIs', () => {
  assert.match(source, /property\.shareOption = pasteboard\.ShareOption\.LOCALDEVICE/);
  assert.match(source, /data\.setProperty\(property\)/);
  assert.doesNotMatch(source, /stopPropagation|preventDefault/);
});
