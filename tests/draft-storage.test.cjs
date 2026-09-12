const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT || 'D:/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/common/DraftService.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText;

function harness(legacy = []) {
  const files = new Map();
  const fds = new Map();
  const storage = new Map([['authEmail', 'Owner@example.com'], ['authToken', 'present'], ['currentAccountId', 7]]);
  const scope = { id: 'service-one', failWrite: false, failSync: false, failRename: false };
  let fd = 0;
  const removed = [];
  const fileIo = {
    accessSync: p => files.has(p), mkdirSync: p => files.set(p, null),
    listFileSync: dir => [...files.keys()].filter(p => p.startsWith(dir + '/') && !p.slice(dir.length + 1).includes('/')).map(p => p.slice(dir.length + 1)),
    readTextSync: p => { if (!files.has(p)) throw new Error('missing'); return files.get(p); },
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    openSync: p => { files.set(p, ''); const file = { fd: ++fd }; fds.set(file.fd, p); return file; },
    writeSync: (handle, data) => {
      if (scope.failWrite) throw new Error('disk full');
      const bytes = Buffer.from(data);
      files.set(fds.get(handle), files.get(fds.get(handle)) + bytes.toString('utf8'));
      return bytes.byteLength;
    },
    fsyncSync: () => { if (scope.failSync) throw new Error('sync failed'); },
    closeSync: file => fds.delete(file.fd),
    renameSync: (from, to) => { if (scope.failRename) throw new Error('rename failed'); files.set(to, files.get(from)); files.delete(from); }
  };
  const modules = {
    '@kit.ArkData': { preferences: { getPreferencesSync: () => ({ getSync: () => legacy.length ? JSON.stringify(legacy) : '' }) } },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return new Uint8Array(Buffer.from(text)); } } } },
    './InstanceRegistry': { InstanceRegistry: { getActiveInstanceId: () => scope.id } },
    './DraftAttachmentStore': { DraftAttachmentStore: { initialize: () => {}, removeUnused: (old, kept) => removed.push([old, kept]) } }
  };
  const module = { exports: {} };
  vm.runInNewContext(compiled, {
    module, exports: module.exports, require: name => modules[name], console,
    AppStorage: { get: k => storage.get(k), set: (k, v) => storage.set(k, v), setOrCreate: (k, v) => { if (!storage.has(k)) storage.set(k, v); } }
  });
  const api = module.exports;
  const reboot = () => api.DraftService.initialize({ filesDir: '/private/files' });
  reboot();
  function draft() {
    const item = new api.MailDraft();
    item.instanceId = scope.id;
    item.ownerEmail = storage.get('authEmail');
    item.senderAccountId = 7;
    item.toEmail = 'recipient@example.org';
    item.subject = 'Subject';
    item.content = 'Body';
    return item;
  }
  return { ...api, files, storage, scope, removed, reboot, draft, fds };
}

test('drafts are isolated by exact instance and primary account identity', () => {
  const h = harness(); const item = h.draft(); h.DraftService.saveDraft(item);
  assert.equal(h.DraftService.getDrafts().length, 1);
  h.scope.id = 'service-two'; assert.equal(h.DraftService.getDrafts().length, 0);
  h.scope.id = 'service-one'; h.storage.set('authEmail', 'other@example.com'); assert.equal(h.DraftService.getDrafts().length, 0);
  h.storage.set('authEmail', 'owner@example.com'); assert.equal(h.DraftService.getDrafts().length, 0);
  h.storage.set('authEmail', 'Owner@example.com'); assert.equal(h.DraftService.getDrafts().length, 1);
});

test('legacy drafts remain unassigned across reboot until explicit import', () => {
  const legacy = [{ id: 1, toEmail: 'old@a.com', subject: 'Old', content: 'Preserved', ccEmail: 'cc@b.com', time: '已保存' }];
  const h = harness(legacy);
  assert.equal(h.DraftService.getDrafts().length, 0); assert.equal(h.DraftService.getUnassignedCount(), 1);
  h.reboot(); assert.equal(h.DraftService.getUnassignedCount(), 1);
  h.DraftService.importUnassigned(h.DraftService.captureOwner());
  assert.equal(h.DraftService.getUnassignedCount(), 0); assert.equal(h.DraftService.getDrafts()[0].ccEmail, 'cc@b.com');
  h.reboot(); assert.equal(h.DraftService.getDrafts().length, 1); assert.equal(h.DraftService.getUnassignedCount(), 0);
  h.DraftService.deleteDraft(1); h.reboot();
  assert.equal(h.DraftService.getUnassignedCount(), 0); assert.equal(h.DraftService.getDrafts().length, 0);
  assert.equal(legacy[0].content, 'Preserved');
});

test('import confirmation captured before switching account cannot bind to new account', () => {
  const h = harness([{ id: 1, toEmail: '', subject: 'Old', content: '' }]);
  const owner = h.DraftService.captureOwner(); h.scope.id = 'service-two';
  assert.throws(() => h.DraftService.importUnassigned(owner));
  assert.equal(h.DraftService.getUnassignedCount(), 1);
});

test('reply context, sender mailbox, pending state and attachment metadata survive restart', () => {
  const h = harness(); const item = h.draft(); item.sendType = 'reply'; item.emailId = 32; item.senderAccountId = 44; item.sendState = 'pending';
  item.attachments = [{ filename: 'photo.jpg', storageName: '123-0.bin', size: 800, type: 'image/jpeg' }];
  const id = h.DraftService.saveDraft(item); h.reboot();
  const saved = h.DraftService.getOwnedDraft(id, h.DraftService.captureOwner());
  assert.equal(saved.emailId, 32); assert.equal(saved.sendType, 'reply'); assert.equal(saved.senderAccountId, 44);
  assert.equal(saved.sendState, 'pending'); assert.equal(saved.attachments[0].storageName, '123-0.bin');
  assert.equal(saved.attachments[0].content, undefined);
});

for (const fault of ['failWrite', 'failSync', 'failRename']) {
  test(fault + ' preserves last durable draft and reports failure', () => {
    const h = harness(); const item = h.draft(); item.id = h.DraftService.saveDraft(item);
    item.content = 'new text'; h.scope[fault] = true;
    assert.throws(() => h.DraftService.saveDraft(item));
    assert.equal(h.DraftService.getDrafts()[0].content, 'Body'); assert.equal(h.fds.size, 0);
    h.scope[fault] = false; h.reboot(); assert.equal(h.DraftService.getDrafts()[0].content, 'Body');
  });
}

test('cross-account update/delete cannot overwrite another owner draft', () => {
  const h = harness(); const item = h.draft(); item.id = h.DraftService.saveDraft(item);
  h.storage.set('authEmail', 'other@example.com');
  assert.throws(() => h.DraftService.deleteDraft(item.id));
  item.ownerEmail = 'other@example.com'; assert.throws(() => h.DraftService.saveDraft(item));
});

test('failed delete keeps draft and attachment metadata', () => {
  const h = harness(); const item = h.draft(); item.id = h.DraftService.saveDraft(item);
  h.scope.failWrite = true;
  assert.throws(() => h.DraftService.deleteDraft(item.id)); assert.equal(h.DraftService.getDrafts().length, 1);
});

test('registered active editor is flushed and never retained after unregister', () => {
  const h = harness(); let calls = 0; const flush = () => calls++;
  h.DraftService.registerEditor(flush); h.DraftService.flushActiveEditor(); assert.equal(calls, 1);
  h.DraftService.unregisterEditor(flush); h.DraftService.flushActiveEditor(); assert.equal(calls, 1);
});

test('corrupt storage is preserved and further writes are blocked', () => {
  const h = harness(); h.files.set('/private/files/mail-drafts-v2/18.json', '{broken'); h.reboot();
  assert.equal(h.storage.get('draftStorageError'), true); assert.throws(() => h.DraftService.saveDraft(h.draft()));
  assert.equal(h.files.get('/private/files/mail-drafts-v2/18.json'), '{broken');
});

function editorHarness() {
  const h = harness();
  let pageSource = fs.readFileSync(path.join(__dirname, '../mail/src/main/ets/pages/ComposePage.ets'), 'utf8');
  // Exercise production state/persistence/send methods. ArkUI layout is validated by the actual Hvigor build.
  const start = pageSource.indexOf('  build() {');
  const end = pageSource.indexOf('  private async requestSend()', start);
  pageSource = pageSource.slice(0, start) + '  build(): void {}\n' + pageSource.slice(end);
  pageSource = pageSource.replace('@Component', '').replace('export struct', 'export class')
    .replace(/@(StorageLink|Watch)\('[^']*'\)\s*/g, '').replace(/@(State|Prop)\s*/g, '');
  const code = ts.transpileModule(pageSource, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  class ApiException extends Error { constructor(code, message, retryable) { super(message); this.code = code; this.retryable = retryable; } }
  const actions = { sends: 0, confirm: 0, failure: null, readFailure: false, savedAtDispatch: '', messages: [] };
  const modules = {
    '../common/Constants': { default: {} },
    '../common/HttpClient': { ApiException },
    '../common/DraftService': h,
    '../common/DraftAttachmentStore': { DraftAttachmentStore: { readForSending: async () => {
      if (actions.readFailure) throw new Error('missing'); return [];
    } } },
    '../common/MailModels': {}, '@kit.CoreFileKit': {},
    '../common/MailService': { MailService: { send: async () => {
      actions.sends++;
      actions.savedAtDispatch = h.DraftService.getDrafts()[0].sendState;
      if (actions.failure) throw actions.failure;
    } } }
  };
  const module = { exports: {} };
  h.storage.set('appPathStack', { pop: () => {} });
  vm.runInNewContext(code, {
    exports: module.exports, module, require: name => { if (!(name in modules)) throw new Error('mock ' + name); return modules[name]; },
    console, Scroller: class {}, setTimeout: () => 1, clearTimeout: () => {}, $r: id => ({ id }),
    AppStorage: { get: k => h.storage.get(k) }
  });
  const context = {
    getPromptAction: () => ({ openToast: info => actions.messages.push(info.message), showDialog: async () => ({ index: actions.confirm }) }),
    getHostContext: () => ({ resourceManager: { getStringSync: id => id } })
  };
  module.exports.ComposePageContent.prototype.getUIContext = () => context;
  const editor = new module.exports.ComposePageContent();
  editor.aboutToAppear();
  editor.toEmail = 'recipient@example.org'; editor.subject = 'Subject'; editor.content = 'Body';
  return { ...h, editor, actions, ApiException };
}

test('send persists an in-flight draft before dispatch and removes it only after success', async () => {
  const h = editorHarness(); await h.editor.sendEmail();
  assert.equal(h.actions.sends, 1); assert.equal(h.actions.savedAtDispatch, 'pending');
  assert.equal(h.DraftService.getDrafts().length, 0); assert.equal(h.editor.completed, true);
});

test('draft persistence failure blocks sending without losing editor content', async () => {
  const h = editorHarness(); h.scope.failSync = true; await h.editor.sendEmail();
  assert.equal(h.actions.sends, 0); assert.equal(h.editor.content, 'Body');
  assert.ok(h.actions.messages.includes('app.string.draft_save_failed'));
});

test('missing attachment blocks sending but preserves the draft', async () => {
  const h = editorHarness(); h.actions.readFailure = true; await h.editor.sendEmail();
  assert.equal(h.actions.sends, 0); assert.equal(h.DraftService.getDrafts().length, 1);
  assert.equal(h.DraftService.getDrafts()[0].content, 'Body');
});

test('network send uncertainty survives restart and never retries without confirmation', async () => {
  const h = editorHarness(); h.actions.failure = new h.ApiException(-1, 'timeout', true);
  await h.editor.sendEmail(); assert.equal(h.actions.sends, 1);
  assert.equal(h.DraftService.getDrafts()[0].sendState, 'unknown');
  h.reboot(); assert.equal(h.DraftService.getDrafts()[0].sendState, 'unknown');
  await h.editor.requestSend(); assert.equal(h.actions.sends, 1);
  h.actions.confirm = 1; h.actions.failure = null; await h.editor.requestSend(); assert.equal(h.actions.sends, 2);
});

test('active instance change prevents a previously opened editor from sending', async () => {
  const h = editorHarness(); h.editor.saveDraftIfNeeded(); h.scope.id = 'service-two';
  await h.editor.sendEmail(); assert.equal(h.actions.sends, 0);
  h.scope.id = 'service-one'; assert.equal(h.DraftService.getDrafts()[0].content, 'Body');
});

test('legacy cc or bcc is preserved and blocks sending rather than silently dropping recipients', async () => {
  const h = editorHarness(); h.editor.ccEmail = 'copy@example.org'; h.editor.saveDraftIfNeeded();
  await h.editor.sendEmail(); assert.equal(h.actions.sends, 0);
  assert.equal(h.DraftService.getDrafts()[0].ccEmail, 'copy@example.org');
});

test('successful send with cleanup failure cannot become a second send in the same editor', async () => {
  const h = editorHarness();
  const original = h.DraftService.deleteDraft;
  h.DraftService.deleteDraft = () => { throw new Error('disk full'); };
  await h.editor.sendEmail(); assert.equal(h.actions.sends, 1); assert.equal(h.editor.completed, true);
  assert.equal(h.DraftService.getDrafts()[0].sendState, 'sent');
  await h.editor.requestSend(); assert.equal(h.actions.sends, 1);
  h.DraftService.deleteDraft = original;
});
