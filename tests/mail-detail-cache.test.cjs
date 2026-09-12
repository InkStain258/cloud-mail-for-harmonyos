const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('../cloud-control-worker/node_modules/typescript');

function moduleFrom(name, mocks = {}, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/common', name + '.ets'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: key => mocks[key], ...globals });
  return exports;
}

function cacheHarness() {
  const models = moduleFrom('MailModels');
  const { MailDetailCache } = moduleFrom('MailDetailCache', { './MailModels': models });
  MailDetailCache.selectScope('a|https://a/api|owner|1');
  const item = (id, body = '') => { const value = new models.MailItem(); value.id = id; value.body = body; return value; };
  return { cache: MailDetailCache, item };
}

test('LRU cache is capped at 32 and access refreshes recency', () => {
  const { cache, item } = cacheHarness();
  for (let id = 1; id <= 32; id++) cache.put(item(id));
  cache.get(1); cache.put(item(33));
  assert.equal(cache.get(2), null); assert.equal(cache.get(1).id, 1); assert.equal(cache.get(33).id, 33);
});

test('a large body cannot bypass the memory budget and summary bodies are not cached', () => {
  const { cache, item } = cacheHarness();
  const brief = item(1); brief.detailLoaded = false; cache.put(brief); assert.equal(cache.get(1), null);
  cache.put(item(2, 'x'.repeat(5 * 1024 * 1024))); assert.equal(cache.get(2), null);
  cache.put(item(3, 'x'.repeat(2 * 1024 * 1024)));
  cache.put(item(4, 'x'.repeat(2 * 1024 * 1024)));
  assert.equal(cache.get(3), null); assert.equal(cache.get(4).id, 4);
});

test('scope includes instance, API, owner and session; any change clears content', () => {
  const { cache, item } = cacheHarness();
  for (const scope of ['b|https://a/api|owner|1', 'b|https://b/api|owner|1', 'b|https://b/api|other|1', 'b|https://b/api|other|2']) {
    cache.put(item(1, 'private')); cache.selectScope(scope); assert.equal(cache.get(1), null);
  }
  cache.put(item(2)); cache.clear(); assert.equal(cache.get(2), null);
});

function capabilityHarness() {
  const state = { instance: 'a', api: 'https://a/api', owner: 'first@a', revision: 1 };
  const requests = []; const responses = [];
  const { NativeCapabilities } = moduleFrom('NativeCapabilities', {
    './SessionService': { SessionService: { getActiveInstanceId: () => state.instance, getApiBaseUrl: () => state.api } },
    './HttpClient': { HttpClient: { get: async url => {
      requests.push(url); const value = responses.shift(); if (value instanceof Error) throw value; return await value;
    } } }
  }, { AppStorage: { get: key => key === 'authEmail' ? state.owner : state.revision } });
  return { NativeCapabilities, state, requests, responses };
}

test('old or malformed capabilities fail closed; only explicit booleans enable features', async () => {
  const h = capabilityHarness(); h.responses.push(new Error('not found'));
  const old = await h.NativeCapabilities.current(); assert.equal(old.summaryDetail, false); assert.equal(old.purposeAddresses, false);
  h.state.revision++; h.responses.push({ data: { summaryDetail: 'true', purposeAddresses: 1 } });
  const invalid = await h.NativeCapabilities.current(); assert.equal(invalid.summaryDetail, false); assert.equal(invalid.purposeAddresses, false);
  h.state.revision++; h.responses.push({ data: { summaryDetail: true, purposeAddresses: true } });
  const valid = await h.NativeCapabilities.current(); assert.equal(valid.summaryDetail, true); assert.equal(valid.purposeAddresses, true);
});

test('concurrent probes deduplicate and a late old instance response never enables a new one', async () => {
  const h = capabilityHarness(); let resolve;
  h.responses.push(new Promise(done => { resolve = done; }));
  const first = h.NativeCapabilities.current(); const duplicate = h.NativeCapabilities.current();
  assert.equal(h.requests.length, 1);
  h.state.instance = 'b'; h.responses.push({ data: { summaryDetail: false, purposeAddresses: false } });
  await h.NativeCapabilities.current(); resolve({ data: { summaryDetail: true, purposeAddresses: true } });
  assert.equal((await first).summaryDetail, false); await duplicate;
  assert.equal((await h.NativeCapabilities.current()).summaryDetail, false); assert.equal(h.requests.length, 2);
});

test('explicit capability retry bypasses a cached unsupported result after a server upgrade', async () => {
  const h = capabilityHarness(); h.responses.push(new Error('not found'));
  assert.equal((await h.NativeCapabilities.current()).purposeAddresses, false);
  h.responses.push({ data: { summaryDetail: true, purposeAddresses: true } });
  assert.equal((await h.NativeCapabilities.current(true)).purposeAddresses, true);
  assert.equal(h.requests.length, 2);
});
