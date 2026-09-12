const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT || 'D:/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../mail/src/main/ets/common');

function load(name, mocks = {}, globals = {}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(root, name + '.ets'), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, console, ...globals,
    require: name => { if (!(name in mocks)) throw new Error('Missing mock ' + name); return mocks[name]; }
  });
  return module.exports;
}

function harness() {
  const models = load('MailModels');
  const { MailDetailCache } = load('MailDetailCache', { './MailModels': models });
  let active = 'one';
  const instances = new Map(['one', 'two'].map(id => [id, {
    instanceId: id, apiBaseUrl: 'https://' + id + '.example/api', localEmail: 'owner@' + id + '.example',
    localRole: 'user', localRoleName: 'Member', accountId: 1, displayName: id
  }]));
  const storage = new Map();
  const events = [];
  const { SessionService } = load('SessionService', {
    '@kit.ArkData': { preferences: {} },
    './Constants': { default: {} },
    './InstanceModels': {},
    './InstanceRegistry': { InstanceRegistry: {
      getInstances: () => [...instances.values()], getDefaultInstanceId: () => 'one',
      find: id => instances.get(id) || null, getActiveInstanceId: () => active,
      getActiveInstance: () => instances.get(active),
      setActiveInstance: id => { if (!instances.has(id)) return false; active = id; return true; },
      updateSession: () => {}, remove: id => instances.delete(id)
    } },
    './SecureTokenStore': { SecureTokenStore: { removeInstanceToken: () => {}, getInstanceToken: () => 'fixture-token' } },
    './MailStatsStore': { MailStatsStore: { reset: () => {}, setOwner: () => {} } },
    './DraftService': { DraftService: { flushActiveEditor: () => events.push('draft-preserved') } },
    './MailDetailCache': { MailDetailCache }
  }, { AppStorage: { get: key => storage.get(key), set: (key, val) => storage.set(key, val),
    setOrCreate: (key, val) => storage.set(key, val) } });
  const item = new models.MailItem();
  item.id = 1; item.detailLoaded = true; item.body = 'Private full mail';
  MailDetailCache.selectScope('one'); MailDetailCache.put(item);
  assert.ok(MailDetailCache.get(1));
  return { SessionService, MailDetailCache, events };
}

test('current-session expiry immediately erases detail cache', () => {
  const h = harness(); h.SessionService.clearSession();
  assert.equal(h.MailDetailCache.get(1), null);
  assert.deepEqual(h.events, ['draft-preserved']);
});
test('global sign-out immediately erases detail cache', () => {
  const h = harness(); h.SessionService.clearAllSessions();
  assert.equal(h.MailDetailCache.get(1), null);
});
test('successful instance switch erases previous account mail content', () => {
  const h = harness(); assert.equal(h.SessionService.switchInstance('two'), true);
  assert.equal(h.MailDetailCache.get(1), null);
});
test('invalid instance switch does not invalidate the active mailbox', () => {
  const h = harness(); assert.equal(h.SessionService.switchInstance('missing'), false);
  assert.ok(h.MailDetailCache.get(1));
});
