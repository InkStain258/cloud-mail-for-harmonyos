import { preferences } from '@kit.ArkData'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { InstanceRegistry } from './InstanceRegistry'
import { DraftAttachment, DraftAttachmentStore } from './DraftAttachmentStore'

export class DraftOwner {
  instanceId: string = ''
  email: string = ''
  accountId: number = 0
}

export class MailDraft {
  id: number = 0
  toEmail: string = ''
  ccEmail: string = ''
  bccEmail: string = ''
  subject: string = ''
  content: string = ''
  time: string = ''
  instanceId: string = ''
  ownerEmail: string = ''
  senderAccountId: number = 0
  sendType: string = ''
  emailId: number = 0
  attachments: DraftAttachment[] = []
  deleted: boolean = false
  sendState: string = ''

  copy(): MailDraft {
    const draft: MailDraft = new MailDraft()
    draft.id = this.id
    draft.toEmail = this.toEmail
    draft.ccEmail = this.ccEmail
    draft.bccEmail = this.bccEmail
    draft.subject = this.subject
    draft.content = this.content
    draft.time = this.time
    draft.instanceId = this.instanceId
    draft.ownerEmail = this.ownerEmail
    draft.senderAccountId = this.senderAccountId
    draft.sendType = this.sendType
    draft.emailId = this.emailId
    draft.attachments = this.attachments.slice()
    draft.deleted = this.deleted
    draft.sendState = this.sendState
    return draft
  }
}

export class DraftService {
  private static directory: string = ''
  private static drafts: MailDraft[] = []
  private static ready: boolean = false
  private static nextId: number = 1
  private static editor: (() => void) | null = null

  static initialize(context: Context): void {
    DraftService.ready = false
    DraftService.drafts = []
    AppStorage.setOrCreate('draftRevision', 0)
    AppStorage.setOrCreate('draftStorageError', false)
    try {
      DraftService.directory = context.filesDir + '/mail-drafts-v2'
      if (!fileIo.accessSync(DraftService.directory)) {
        fileIo.mkdirSync(DraftService.directory)
      }
      DraftAttachmentStore.initialize(context)
      const names: string[] = fileIo.listFileSync(DraftService.directory)
      const knownIds: number[] = []
      for (let index = 0; index < names.length; index++) {
        if (!/^[0-9]+\.json$/.test(names[index])) {
          continue
        }
        const item: MailDraft = DraftService.parse(fileIo.readTextSync(DraftService.directory + '/' + names[index]))
        if (names[index] !== item.id.toString() + '.json') {
          throw new Error('Draft file identity mismatch')
        }
        knownIds.push(item.id)
        if (!item.deleted) {
          DraftService.drafts.push(item)
        }
      }
      // Legacy records cannot be attributed to the current login. Preserve them until explicit import.
      // Never clear legacy storage. Versioned files/tombstones suppress already handled legacy IDs.
      const legacy: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'cloud_mail_drafts' })
      const raw: string = legacy.getSync('items', '') as string
      if (raw !== '') {
        const items: MailDraft[] = JSON.parse(raw) as MailDraft[]
        for (let index = 0; index < items.length; index++) {
          if (knownIds.indexOf(items[index].id) < 0) {
            const item: MailDraft = DraftService.parse(JSON.stringify(items[index]))
            item.instanceId = ''
            item.ownerEmail = ''
            item.senderAccountId = 0
            item.sendType = ''
            item.emailId = 0
            DraftService.drafts.push(item)
          }
        }
      }
      DraftService.nextId = Date.now()
      for (let index = 0; index < knownIds.length; index++) {
        DraftService.nextId = Math.max(DraftService.nextId, knownIds[index] + 1)
      }
      DraftService.ready = true
      AppStorage.set('draftStorageError', false)
    } catch (err) {
      AppStorage.set('draftStorageError', true)
      console.error('Draft storage unavailable; original data preserved')
    }
  }

  static captureOwner(): DraftOwner {
    const owner: DraftOwner = new DraftOwner()
    owner.instanceId = InstanceRegistry.getActiveInstanceId()
    owner.email = ((AppStorage.get('authEmail') as string | undefined) || '').trim()
    owner.accountId = (AppStorage.get('currentAccountId') as number | undefined) || 0
    return owner
  }

  static isCurrentOwner(owner: DraftOwner): boolean {
    const current: DraftOwner = DraftService.captureOwner()
    return owner.instanceId !== '' && owner.email !== '' && owner.instanceId === current.instanceId &&
      owner.email === current.email && ((AppStorage.get('authToken') as string | undefined) || '') !== ''
  }

  static getDrafts(): MailDraft[] {
    const owner: DraftOwner = DraftService.captureOwner()
    return DraftService.drafts.filter((item: MailDraft): boolean => DraftService.belongsTo(item, owner))
      .map((item: MailDraft): MailDraft => item.copy())
      .sort((left: MailDraft, right: MailDraft): number => right.time.localeCompare(left.time))
  }

  static getOwnedDraft(id: number, owner: DraftOwner): MailDraft {
    const item: MailDraft | undefined = DraftService.drafts.find((draft: MailDraft): boolean => draft.id === id)
    if (!item || !DraftService.belongsTo(item, owner)) {
      throw new Error('Draft owner mismatch')
    }
    return item.copy()
  }

  static getUnassignedCount(): number {
    return DraftService.drafts.filter((item: MailDraft): boolean => item.instanceId === '' || item.ownerEmail === '').length
  }

  static importUnassigned(owner: DraftOwner): void {
    if (!DraftService.isCurrentOwner(owner)) {
      throw new Error('Draft owner changed')
    }
    const originals: MailDraft[] = DraftService.drafts.slice()
    for (let index = 0; index < originals.length; index++) {
      if (originals[index].instanceId === '' || originals[index].ownerEmail === '') {
        const imported: MailDraft = originals[index].copy()
        imported.instanceId = owner.instanceId
        imported.ownerEmail = owner.email
        imported.senderAccountId = owner.accountId
        DraftService.saveDraft(imported)
      }
    }
  }

  static saveDraft(draft: MailDraft): number {
    if (!DraftService.ready || draft.instanceId === '' || draft.ownerEmail === '') {
      throw new Error('Draft storage or owner unavailable')
    }
    const next: MailDraft = draft.copy()
    if (next.id === 0) {
      next.id = DraftService.nextId++
    }
    const old: MailDraft | undefined = DraftService.drafts.find((item: MailDraft): boolean => item.id === next.id)
    if (old && old.instanceId !== '' && (old.instanceId !== next.instanceId || old.ownerEmail !== next.ownerEmail)) {
      throw new Error('Cannot overwrite another account draft')
    }
    next.time = new Date().toISOString()
    DraftService.persist(next)
    DraftService.drafts = DraftService.drafts.filter((item: MailDraft): boolean => item.id !== next.id)
    if (!next.deleted) {
      DraftService.drafts.unshift(next)
    }
    if (old) {
      DraftAttachmentStore.removeUnused(old.attachments, next.deleted ? [] : next.attachments)
    }
    DraftService.notifyChange()
    return next.id
  }

  static deleteDraft(id: number, owner: DraftOwner = DraftService.captureOwner()): void {
    const item: MailDraft = DraftService.getOwnedDraft(id, owner)
    const deleted: MailDraft = new MailDraft()
    deleted.id = id
    deleted.instanceId = item.instanceId
    deleted.ownerEmail = item.ownerEmail
    deleted.deleted = true
    // Tombstones prevent imported legacy drafts from reappearing after restart.
    DraftService.saveDraft(deleted)
  }

  static registerEditor(flush: () => void): void {
    DraftService.editor = flush
  }

  static unregisterEditor(flush: () => void): void {
    if (DraftService.editor === flush) {
      DraftService.editor = null
    }
  }

  static flushActiveEditor(): void {
    if (DraftService.editor !== null) {
      DraftService.editor()
    }
  }

  private static belongsTo(item: MailDraft, owner: DraftOwner): boolean {
    return !item.deleted && owner.email !== '' && item.instanceId === owner.instanceId && item.ownerEmail === owner.email
  }

  private static parse(raw: string): MailDraft {
    const value: MailDraft = JSON.parse(raw) as MailDraft
    if (!Number.isSafeInteger(value.id) || value.id <= 0 || typeof value.toEmail !== 'string' ||
      typeof value.subject !== 'string' || typeof value.content !== 'string') {
      throw new Error('Invalid draft storage')
    }
    const item: MailDraft = new MailDraft()
    item.id = value.id
    item.toEmail = value.toEmail
    item.ccEmail = value.ccEmail || ''
    item.bccEmail = value.bccEmail || ''
    item.subject = value.subject
    item.content = value.content
    item.time = value.time || ''
    item.instanceId = value.instanceId || ''
    item.ownerEmail = (value.ownerEmail || '').trim()
    item.senderAccountId = value.senderAccountId || 0
    item.sendType = value.sendType || ''
    item.emailId = value.emailId || 0
    item.attachments = value.attachments || []
    item.deleted = value.deleted === true
    item.sendState = value.sendState || ''
    return item
  }

  private static persist(item: MailDraft): void {
    const path: string = DraftService.directory + '/' + item.id.toString() + '.json'
    const tempPath: string = path + '.tmp'
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(item))
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      let offset: number = 0
      while (offset < bytes.byteLength) {
        const written: number = fileIo.writeSync(file.fd, bytes.buffer.slice(offset))
        if (written <= 0) {
          throw new Error('Draft write incomplete')
        }
        offset += written
      }
      fileIo.fsyncSync(file.fd)
      fileIo.closeSync(file)
      file = null
      fileIo.renameSync(tempPath, path)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static notifyChange(): void {
    const revision: number = (AppStorage.get('draftRevision') as number | undefined) || 0
    AppStorage.set('draftRevision', revision + 1)
  }
}
