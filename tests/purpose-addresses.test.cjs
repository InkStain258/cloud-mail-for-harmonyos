const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('../cloud-control-worker/node_modules/typescript');

function harness() {
  const state = { instance: 'first', api: 'https://first.example/api', email: 'owner@first.example', accountId: 7, token: 'present', revision: 1 };
  const cache = new Map();
  const disk = new Map();
  let failFlush = false;
  const preferences = {
    getSync: (key, fallback) => cache.has(key) ? cache.get(key) : fallback,
    putSync: (key, value) => cache.set(key, value),
    flushSync: () => {
      if (failFlush) throw new Error('Storage unavailable');
      for (const [key, value] of cache) disk.set(key, value);
    }
  };
  const modules = {
    '@kit.ArkData': { preferences: { getPreferencesSync: () => preferences } },
    './SessionService': { SessionService: { getActiveInstanceId: () => state.instance, getApiBaseUrl: () => state.api } }
  };
  const load = name => {
    const exports = {};
    const code = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/common/' + name + '.ets'), 'utf8');
    const compiled = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } });
    vm.runInNewContext(compiled.outputText, {
      exports, require: name => modules[name],
      AppStorage: { get: name => ({ authEmail: state.email, currentAccountId: state.accountId, authToken: state.token, sessionRevision: state.revision })[name] }
    });
    modules['./' + name] = exports;
    return exports;
  };
  const rules = load('PurposeAddressRules').PurposeAddressRules;
  const store = load('PurposeAddressStore').PurposeAddressStore;
  return { rules, store, state, cache, disk, fail: value => { failFlush = value; } };
}

test('creates a purpose alias while preserving the actual mailbox local part', () => {
  const { rules } = harness();
  const result = rules.create('Owner.Name@example.com', ' SHOP_2026 ', ' Shopping ');
  assert.equal(result.address, 'Owner.Name+shop_2026@example.com');
  assert.equal(result.label, 'Shopping');
  assert.equal(result.tag, 'shop_2026');
});

test('rejects delimiter injection, controls, ambiguous nested aliases, and invalid tags', () => {
  const { rules } = harness();
  for (const tag of ['', '+shop', 'shop@evil.test', 'shop\r\nX: y', '../x', '-shop', '购物', 'a'.repeat(33)]) {
    assert.throws(() => rules.create('name@example.com', tag, 'Shopping'), /purpose_invalid_tag/);
  }
  for (const base of ['name+tag@example.com', 'two@@example.com', '.name@example.com', 'a..b@example.com', 'name@bad..example', 'name\r\n@example.com']) {
    assert.equal(rules.isBaseMailbox(base), false);
    assert.throws(() => rules.create(base, 'shop', 'Shopping'), /purpose_invalid_mailbox/);
  }
  for (const label of ['', '\r\n', 'bad\nlabel', 'a'.repeat(31)]) {
    assert.throws(() => rules.create('name@example.com', 'shop', label), /purpose_invalid_label/);
  }
});

test('limits the complete local part to 64 characters', () => {
  const { rules } = harness();
  assert.equal(rules.create('a'.repeat(62) + '@example.com', 'x', 'Valid').address.split('@')[0].length, 64);
  assert.throws(() => rules.create('a'.repeat(63) + '@example.com', 'x', 'Too long'), /purpose_address_too_long/);
});

test('persists labels and rejects duplicate tags case-insensitively', () => {
  const { store, disk } = harness();
  const scope = store.capture('owner@first.example');
  store.add({}, scope, 'shop', 'Shopping');
  assert.equal(store.load({}, scope)[0].address, 'owner+shop@first.example');
  assert.equal(disk.size, 1);
  assert.throws(() => store.add({}, scope, 'SHOP', 'Another'), /purpose_duplicate/);
  assert.equal(store.load({}, scope).length, 1);
});

test('isolates labels by instance, API origin, primary owner and base mailbox', () => {
  const { store, state } = harness();
  store.add({}, store.capture('shared@first.example'), 'one', 'First');
  assert.equal(store.load({}, store.capture('other@first.example')).length, 0);
  state.instance = 'second';
  assert.equal(store.load({}, store.capture('shared@first.example')).length, 0);
  state.instance = 'first';
  state.api = 'https://replaced.example/api';
  assert.equal(store.load({}, store.capture('shared@first.example')).length, 0);
  state.api = 'https://first.example/api';
  state.email = 'someone@first.example';
  assert.equal(store.load({}, store.capture('shared@first.example')).length, 0);
  state.email = 'owner@first.example';
  assert.equal(store.load({}, store.capture('shared@first.example')).length, 1);
  state.accountId = 100;
  assert.equal(store.load({}, store.capture('shared@first.example')).length, 0, 'a recreated primary mailbox must not inherit the previous account labels');
});

test('stale sheets cannot read, save or remove labels after account switching or logout', () => {
  const { store, state } = harness();
  const stale = store.capture('owner@first.example');
  store.add({}, stale, 'shop', 'Shopping');
  state.revision++;
  assert.equal(store.isCurrent(stale), false);
  assert.throws(() => store.add({}, stale, 'news', 'News'), /purpose_session_changed/);
  assert.throws(() => store.remove({}, stale, 'shop'), /purpose_session_changed/);
  const current = store.capture('owner@first.example');
  state.token = '';
  assert.throws(() => store.load({}, current), /purpose_session_changed/);
});

test('removal only changes local labels and leaves other labels intact', () => {
  const { store } = harness();
  const scope = store.capture('owner@first.example');
  store.add({}, scope, 'shop', 'Shopping');
  store.add({}, scope, 'news', 'News');
  const result = store.remove({}, scope, 'shop');
  assert.deepEqual(Array.from(result, item => item.tag), ['news']);
  assert.deepEqual(Array.from(store.load({}, scope), item => item.tag), ['news']);
});

test('failed flush does not acknowledge or retain an unsaved in-memory label', () => {
  const { store, fail, disk } = harness();
  const scope = store.capture('owner@first.example');
  store.add({}, scope, 'shop', 'Shopping');
  const before = Array.from(disk.entries());
  fail(true);
  assert.throws(() => store.add({}, scope, 'news', 'News'), /purpose_storage_failed/);
  assert.equal(store.load({}, scope).length, 1);
  assert.deepEqual(Array.from(disk.entries()), before);
});

test('corrupt or mismatched stored data is not silently cleared or overwritten', () => {
  const { store, cache } = harness();
  const scope = store.capture('owner@first.example');
  store.add({}, scope, 'shop', 'Shopping');
  const key = Array.from(cache.keys())[0];
  const raw = JSON.stringify([{ tag: 'shop', label: 'Shopping', address: 'other+shop@first.example' }]);
  cache.set(key, raw);
  assert.throws(() => store.add({}, scope, 'news', 'News'), /purpose_storage_failed/);
  assert.equal(cache.get(key), raw);
});

test('caps local labels per mailbox', () => {
  const { rules, store } = harness();
  const scope = store.capture('owner@first.example');
  for (let index = 0; index < rules.LIMIT; index++) store.add({}, scope, 'tag' + index, 'Label');
  assert.throws(() => store.add({}, scope, 'extra', 'Label'), /purpose_limit/);
});

test('UI only enables supported capability and all new resource strings exist in both languages', () => {
  const panel = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/components/PurposeAddressPanel.ets'), 'utf8');
  assert.match(panel, /info\.purposeAddresses && PurposeAddressRules\.isBaseMailbox/);
  assert.match(panel, /\.enabled\(this\.supported\)/);
  assert.match(panel, /if \(!this\.supported \|\| !this\.storageReady\)/);
  assert.match(panel, /this\.checkCapability\(true\)/);
  assert.match(panel, /NativeCapabilities\.current\(forceRefresh\)/);
  assert.match(panel, /private async showToast[\s\S]*try \{[\s\S]*await this\.getUIContext\(\)\.getPromptAction\(\)\.openToast[\s\S]*catch/);
  for (const locale of ['base', 'en_US']) {
    const resources = JSON.parse(fs.readFileSync(path.join(__dirname, '../mail/src/main/resources/' + locale + '/element/purpose_strings.json'), 'utf8'));
    const names = new Set(resources.string.map(item => item.name));
    for (const match of panel.matchAll(/app\.string\.(purpose_[a-z_]+)/g)) assert.ok(names.has(match[1]), match[1]);
  }
});
