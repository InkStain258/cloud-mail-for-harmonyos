const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('../cloud-control-worker/node_modules/typescript');

function harness() {
  const state = { instance: 'first', api: 'https://first.example/api', email: 'a@first.example', revision: 1 };
  const calls = [];
  const responses = [];
  const fetch = async (kind, cursor) => {
    calls.push({ kind, cursor });
    const response = responses.shift();
    if (response instanceof Error) throw response;
    return await response;
  };
  const modules = {
    './MailService': { MailService: {
      loadInboxPage: cursor => fetch('inbox', cursor),
      loadSentPage: cursor => fetch('sent', cursor),
      loadStarredPage: cursor => fetch('starred', cursor)
    } },
    './SessionService': { SessionService: {
      getActiveInstanceId: () => state.instance,
      getApiBaseUrl: () => state.api
    } }
  };
  const exports = {};
  const code = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/common/MailHistoryLoader.ets'), 'utf8');
  const compiled = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } });
  vm.runInNewContext(compiled.outputText, {
    exports,
    require: name => modules[name],
    AppStorage: { get: name => name === 'authEmail' ? state.email : state.revision }
  });
  const loader = new exports.MailHistoryLoader(exports.MailHistoryKind.Inbox);
  loader.reset();
  return { loader, calls, responses, state, types: exports };
}

function page(ids, more = true, total = -1) {
  return { items: ids.map(id => ({ id })), nextCursor: ids.at(-1) || 0, hasMore: more, total };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

test('continues unknown-total history beyond first page with a stable cursor', async () => {
  const h = harness();
  h.responses.push(page([100, 99]), page([98, 97], false));
  assert.equal(await h.loader.loadNext(), true);
  assert.equal(h.loader.hasMore, true);
  assert.equal(await h.loader.loadNext(), true);
  assert.deepEqual(h.calls.map(call => call.cursor), [0, 99]);
  assert.equal(h.loader.items.length, 4);
  assert.equal(h.loader.hasMore, false);
  assert.equal(await h.loader.loadNext(), false);
  assert.equal(h.calls.length, 2);
});

test('overlapping page data is deduplicated including duplicate IDs within one page', async () => {
  const h = harness();
  h.responses.push(page([100, 99]), page([99, 98, 98], false));
  await h.loader.loadNext();
  await h.loader.loadNext();
  assert.deepEqual(Array.from(h.loader.items, item => item.id), [100, 99, 98]);
});

test('a service ignoring the cursor stops instead of requesting the same page forever', async () => {
  const h = harness();
  h.responses.push(page([100, 99]), page([100, 99]));
  await h.loader.loadNext();
  await h.loader.loadNext();
  assert.equal(h.loader.stalled, true);
  assert.equal(h.loader.hasMore, false);
  assert.equal(await h.loader.loadNext(), false);
});

test('only one request is active for a generation', async () => {
  const h = harness();
  const pending = deferred();
  h.responses.push(pending.promise);
  const first = h.loader.loadNext();
  assert.equal(await h.loader.loadNext(), false);
  pending.resolve(page([2], false));
  await first;
  assert.equal(h.calls.length, 1);
});

test('a non-progressing cursor is incomplete even when service marks hasMore false', async () => {
  const h = harness();
  h.responses.push(page([100, 99]), page([100, 99], false));
  await h.loader.loadNext();
  await h.loader.loadNext();
  assert.equal(h.loader.stalled, true);
  assert.equal(h.loader.hasMore, false);
});

test('an invalid zero cursor on a non-empty page is not a complete search', async () => {
  const h = harness();
  h.responses.push({ items: [{ id: 3 }], nextCursor: 0, hasMore: false, total: -1 });
  await h.loader.loadNext();
  assert.equal(h.loader.stalled, true);
});

test('cancel retains loaded results and rejects the in-flight next page', async () => {
  const h = harness();
  h.responses.push(page([9, 8]));
  await h.loader.loadNext();
  const pending = deferred();
  h.responses.push(pending.promise);
  const next = h.loader.loadNext();
  h.loader.cancel();
  pending.resolve(page([7, 6]));
  assert.equal(await next, false);
  assert.deepEqual(Array.from(h.loader.items, item => item.id), [9, 8]);
  h.responses.push(page([7], false));
  assert.equal(await h.loader.loadNext(), true);
  assert.deepEqual(h.calls.map(call => call.cursor), [0, 8, 8]);
});

test('old response cannot unlock or replace a newer in-flight search', async () => {
  const h = harness();
  const first = deferred();
  const second = deferred();
  h.responses.push(first.promise, second.promise);
  const older = h.loader.loadNext();
  h.loader.cancel();
  const newer = h.loader.loadNext();
  first.resolve(page([9]));
  assert.equal(await older, false);
  assert.equal(h.loader.loading, true);
  second.resolve(page([8], false));
  assert.equal(await newer, true);
  assert.deepEqual(Array.from(h.loader.items, item => item.id), [8]);
});

test('an instance switch discards old data and old errors', async () => {
  const h = harness();
  const pending = deferred();
  h.responses.push(pending.promise);
  const old = h.loader.loadNext();
  h.state.instance = 'second';
  pending.reject(new Error('old request failed'));
  assert.equal(await old, false);
  assert.equal(h.loader.items.length, 0);
  h.loader.reset();
  h.responses.push(page([3], false));
  assert.equal(await h.loader.loadNext(), true);
});

test('same instance after logout/login still rejects prior-session responses', async () => {
  const h = harness();
  const pending = deferred();
  h.responses.push(pending.promise);
  const old = h.loader.loadNext();
  h.state.revision++;
  pending.resolve(page([7]));
  assert.equal(await old, false);
  assert.equal(h.loader.items.length, 0);
});

test('network failure preserves history and cursor for retry', async () => {
  const h = harness();
  h.responses.push(page([8, 7]), new Error('offline'), page([6], false));
  await h.loader.loadNext();
  await assert.rejects(h.loader.loadNext(), /offline/);
  assert.equal(h.loader.items.length, 2);
  assert.equal(h.loader.loading, false);
  await h.loader.loadNext();
  assert.deepEqual(h.calls.map(call => call.cursor), [0, 7, 7]);
});

test('sent and starred use their own paging endpoints', async () => {
  const h = harness();
  for (const kind of [h.types.MailHistoryKind.Sent, h.types.MailHistoryKind.Starred]) {
    const loader = new h.types.MailHistoryLoader(kind);
    loader.reset();
    h.responses.push(page([5], false));
    await loader.loadNext();
  }
  assert.deepEqual(h.calls.map(call => call.kind), ['sent', 'starred']);
});

test('refresh cannot restore stale items from a concurrent local star/delete callback', async () => {
  const h = harness();
  const pending = deferred();
  h.responses.push(pending.promise);
  const loading = h.loader.loadNext();
  h.loader.replaceItems([{ id: 20 }]);
  pending.resolve(page([10], false));
  await loading;
  assert.deepEqual(Array.from(h.loader.items, item => item.id), [10]);
});
