const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT || 'D:/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../mail/src/main/ets');

function load(relative, mocks = {}, globals = {}) {
  const filename = path.join(root, relative);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(compiled, {
    exports: module.exports, module, console,
    require: name => { if (name in mocks) return mocks[name]; throw new Error('Missing mock: ' + name); },
    ...globals
  }, { filename });
  return module.exports;
}

const { MailResourceUrl } = load('common/MailResourceUrl.ets');
test('attachments use the originating API path, not the anchor service', () => {
  assert.equal(MailResourceUrl.attachmentUrl('https://second.example/api/', 'mail/file.pdf'),
    'https://second.example/api/oss/mail/file.pdf');
});
test('attachment keys remain object keys, even with spaces and URL metacharacters', () => {
  assert.equal(MailResourceUrl.attachmentUrl('https://second.example/api', 'a b?#%.pdf'),
    'https://second.example/api/oss/a%20b%3F%23%25.pdf');
});
test('attachment keys cannot redirect requests or traverse paths', () => {
  for (const key of ['https://elsewhere.example/x', '//elsewhere/x', '../private', 'a/../b', 'a\\b', '']) {
    assert.throws(() => MailResourceUrl.attachmentUrl('https://second.example/api', key));
  }
});
test('inline media uses instance config and safely falls back to that instance', () => {
  assert.equal(MailResourceUrl.mediaBase('', 'https://second.example/api'), 'https://second.example/api/oss/');
  assert.equal(MailResourceUrl.mediaBase('cdn.example/mail', 'https://second.example/api'), 'https://cdn.example/mail/');
  assert.throws(() => MailResourceUrl.mediaBase('https://user:secret@cdn.example', 'https://second.example/api'));
});

function harness() {
  const storage = new Map([['authEmail', 'owner@second.example'], ['currentAccountId', 22], ['mailRevision', 0]]);
  const scope = { id: 'second', api: 'https://second.example/api' };
  const calls = [];
  const counts = [];
  let payload = { list: [] };
  let capabilities = { summaryDetail: false, purposeAddresses: false };
  class ApiException extends Error { constructor(code, message, retryable) { super(message); this.code = code; this.retryable = retryable; } }
  const models = load('common/MailModels.ets');
  const cache = load('common/MailDetailCache.ets', { './MailModels': models });
  const { MailService } = load('common/MailService.ets', {
    './HttpClient': { ApiException },
    '../api/EmailApi': { EmailApi: {
      list: async (...args) => { calls.push(['list', ...args]); return { code: 200, data: payload }; },
      listStarred: async (...args) => { calls.push(['star', ...args]); return { code: 200, data: payload }; },
      detail: async id => { calls.push(['detail', id]); return { code: 200, data: payload }; },
      send: async json => { calls.push(['send', JSON.parse(json)]); return { code: 200 }; }
    } },
    './MailModels': models,
    './MailDetailCache': cache,
    './NativeCapabilities': { NativeCapabilities: {
      current: async () => capabilities,
      sessionKey: () => [scope.id, scope.api, storage.get('authEmail'), storage.get('sessionRevision') || 0].join('|')
    } },
    './SessionService': { SessionService: { getActiveInstanceId: () => scope.id, getApiBaseUrl: () => scope.api } },
    './DateTimeUtils': { DateTimeUtils: { formatUtcDateTime: value => value } },
    './MailStatsStore': { MailStatsStore: {
      syncReceive: value => counts.push(['receive', value]), syncSent: value => counts.push(['sent', value]),
      syncStar: value => counts.push(['star', value]), incrementSent: () => counts.push(['sent+1'])
    } }
  }, { AppStorage: { get: key => storage.get(key), set: (key, value) => storage.set(key, value) } });
  return { MailService, models, storage, scope, calls, counts,
    setPayload: value => { payload = value; }, setCapabilities: value => { capabilities = value; } };
}
function rows(start, count) {
  return Array.from({ length: count }, (_, index) => ({ emailId: start - index, accountId: 22,
    sendEmail: 'sender@example.com', name: 'Sender', subject: 'Subject', text: 'Body', content: '',
    cc: null, bcc: null, toEmail: 'owner@second.example', toName: '', type: 0, unread: 0,
    createTime: '2026-09-01', isStar: 0, attList: [] }));
}
test('legacy starred page without total still permits subsequent pages', async () => {
  const h = harness(); h.setPayload({ list: rows(100, 50) });
  const page = await h.MailService.loadStarredPage(0);
  assert.equal(page.total, -1); assert.equal(page.hasMore, true); assert.equal(page.nextCursor, 51);
  assert.equal(h.counts.length, 0, 'one page must not overwrite the global starred count');
});
test('short later pages end pagination without claiming page size is the global total', async () => {
  const h = harness(); h.setPayload({ list: rows(50, 8) });
  const page = await h.MailService.loadStarredPage(51);
  assert.equal(page.hasMore, false); assert.equal(page.total, -1); assert.equal(h.counts.length, 0);
});
test('short first pages can provide an exact count', async () => {
  const h = harness(); h.setPayload({ list: rows(40, 8) });
  const page = await h.MailService.loadStarredPage(0);
  assert.equal(page.total, 8); assert.deepEqual(h.counts, [['star', 8]]);
});
test('sent pagination passes email cursor and preserves original account metadata', async () => {
  const h = harness(); h.setPayload({ list: rows(90, 2), total: 92 });
  const page = await h.MailService.loadSentPage(91);
  assert.deepEqual(h.calls[0], ['list', 22, 0, 91, 0, 50, 1, true]);
  assert.equal(page.items[0].instanceId, 'second');
  assert.equal(page.items[0].apiBaseUrl, 'https://second.example/api');
  assert.equal(page.items[0].copy().ownerEmail, 'owner@second.example');
});
test('non-advancing cursor is bounded rather than looping forever', async () => {
  const h = harness(); h.setPayload({ list: rows(100, 50) });
  const page = await h.MailService.loadInboxPage(51);
  assert.equal(page.hasMore, false);
});
test('draft from another instance or primary account cannot be sent', async () => {
  const h = harness();
  await assert.rejects(() => h.MailService.send('to@example.com', '', '', 's', 'body', '', 0, [], 'first', 'owner@second.example', 22));
  await assert.rejects(() => h.MailService.send('to@example.com', '', '', 's', 'body', '', 0, [], 'second', 'other@example.com', 22));
  assert.equal(h.calls.length, 0);
});
test('explicit draft sender identity survives current submail selection changes', async () => {
  const h = harness();
  await h.MailService.send('to@example.com', '', '', 's', 'body', 'reply', 80, [], 'second', 'owner@second.example', 71);
  assert.equal(h.calls[0][1].accountId, 71); assert.equal(h.calls[0][1].emailId, 80);
});
test('unsupported CC/BCC is never silently discarded on send', async () => {
  const h = harness();
  await assert.rejects(() => h.MailService.send('to@example.com', 'cc@example.com', '', 's', 'body', '', 0, []));
  assert.equal(h.calls.length, 0);
});

test('summary-capable instances request brief lists and tolerate omitted attachment/header fields', async () => {
  const h = harness(); h.setCapabilities({ summaryDetail: true });
  h.setPayload({ list: [{ emailId: 41, type: 0, listText: 'brief only', code: '123456', toEmail: 'owner@second.example' }] });
  const page = await h.MailService.loadInboxPage(0);
  assert.equal(h.calls[0].at(-1), false);
  assert.equal(page.items[0].body, 'brief only');
  assert.equal(page.items[0].detailLoaded, false);
  assert.equal(page.items[0].verificationCode, '123456');
  assert.equal(page.items[0].attList.length, 0);
  assert.equal(page.items[0].accountId, 0);
});

test('explicit body search requests full data even when the server supports summaries', async () => {
  const h = harness(); h.setCapabilities({ summaryDetail: true });
  h.setPayload({ list: rows(30, 1) });
  const page = await h.MailService.loadInboxPage(0, true);
  assert.equal(h.calls[0].at(-1), true);
  assert.equal(page.items[0].detailLoaded, true);
});

test('mail detail is fetched once, includes attachments, and returns defensive cache copies', async () => {
  const h = harness(); h.setCapabilities({ summaryDetail: true });
  h.setPayload({ list: [{ emailId: 40, type: 0, listText: 'brief', toEmail: 'owner@second.example' }] });
  const summary = (await h.MailService.loadInboxPage(0)).items[0];
  const remote = rows(40, 1)[0]; remote.content = '<p>complete message</p>';
  remote.attList = [{ filename: 'a.pdf', key: 'mail/a.pdf' }]; h.setPayload(remote);
  const first = await h.MailService.loadDetail(summary);
  assert.equal(first.detailLoaded, true); assert.equal(first.accountId, 22);
  assert.equal(first.htmlContent, '<p>complete message</p>');
  assert.equal(first.attachmentKeys[0], 'mail/a.pdf');
  first.body = 'caller edit'; first.attList.push('fake');
  const second = await h.MailService.loadDetail(summary);
  assert.equal(second.body, 'Body'); assert.equal(second.attList.length, 1);
  assert.equal(h.calls.filter(call => call[0] === 'detail').length, 1);
});

test('detail never loads mail from a different instance, API origin, or account', async () => {
  const h = harness(); const item = new h.models.MailItem();
  item.id = 1; item.instanceId = 'second'; item.apiBaseUrl = h.scope.api; item.ownerEmail = h.storage.get('authEmail');
  for (const field of ['instanceId', 'apiBaseUrl', 'ownerEmail']) {
    const other = item.copy(); other[field] = 'other';
    await assert.rejects(h.MailService.loadDetail(other), /账号已切换/);
  }
  assert.equal(h.calls.length, 0);
});

test('a renewed login cannot reuse old-session cached mail with the same numeric ID', async () => {
  const h = harness(); h.setCapabilities({ summaryDetail: true });
  h.setPayload({ list: [{ emailId: 40, type: 0, listText: 'brief', toEmail: 'owner@second.example' }] });
  const summary = (await h.MailService.loadInboxPage(0)).items[0];
  h.setPayload(rows(40, 1)[0]); await h.MailService.loadDetail(summary);
  h.storage.set('sessionRevision', 2);
  const remote = rows(40, 1)[0]; remote.text = 'new login content'; h.setPayload(remote);
  assert.equal((await h.MailService.loadDetail(summary)).body, 'new login content');
  assert.equal(h.calls.filter(call => call[0] === 'detail').length, 2);
});

test('unexpected detail IDs and oversized or multiline verification codes are rejected', async () => {
  const h = harness(); h.setCapabilities({ summaryDetail: true });
  h.setPayload({ list: [{ emailId: 40, type: 0, listText: 'brief', code: '123\n456' }] });
  const summary = (await h.MailService.loadInboxPage(0)).items[0];
  assert.equal(summary.verificationCode, ''); h.setPayload(rows(39, 1)[0]);
  await assert.rejects(h.MailService.loadDetail(summary), /详情返回格式/);
});

test('statistics are scoped to instance even when two services use the same email', () => {
  const values = new Map([['authEmail', 'same@example.com']]);
  let instanceId = 'first';
  const { MailStatsStore } = load('common/MailStatsStore.ets', {
    './InstanceRegistry': { InstanceRegistry: { getActiveInstanceId: () => instanceId } }
  }, { AppStorage: {
    get: key => values.get(key), set: (key, value) => values.set(key, value),
    setOrCreate: (key, value) => { if (!values.has(key)) values.set(key, value); }
  } });
  MailStatsStore.initialize(); MailStatsStore.sync(99, 20, 10);
  assert.equal(MailStatsStore.hasCurrentStats(), true);
  instanceId = 'second'; MailStatsStore.setOwner('same@example.com');
  assert.equal(MailStatsStore.hasCurrentStats(), false);
  assert.equal(values.get('mailReceiveCount'), 0);
  assert.equal(values.get('mailReceiveCountReady'), false);
  MailStatsStore.incrementSent(); MailStatsStore.adjustStar(1);
  assert.equal(values.get('mailSentCountReady'), false, 'one sent email is not a known total');
  assert.equal(values.get('mailStarCountReady'), false, 'one added star is not a known total');
  assert.equal(values.get('mailSentCount'), 0);
  assert.equal(values.get('mailStarCount'), 0);
  MailStatsStore.adjustStar(-1);
  assert.equal(values.get('mailStarCountReady'), false, 'unstar must not turn unknown into zero');
  MailStatsStore.syncSent(20); MailStatsStore.syncStar(2);
  MailStatsStore.incrementSent(); MailStatsStore.adjustStar(-1);
  assert.equal(values.get('mailSentCount'), 21);
  assert.equal(values.get('mailStarCount'), 1);
  assert.equal(values.get('mailSentCountReady'), true);
  assert.equal(values.get('mailStarCountReady'), true);
});
