import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { MailAttachment } from './MailModels'

export class DraftAttachment {
  filename: string = ''
  storageName: string = ''
  size: number = 0
  type: string = 'application/octet-stream'
}

export class DraftAttachmentStore {
  private static directory: string = ''
  private static sequence: number = 0

  static initialize(context: Context): void {
    DraftAttachmentStore.directory = context.filesDir + '/mail-draft-attachments'
    if (!fileIo.accessSync(DraftAttachmentStore.directory)) {
      fileIo.mkdirSync(DraftAttachmentStore.directory)
    }
  }

  static async importUri(uri: string): Promise<DraftAttachment> {
    let source: fileIo.File | null = null
    let destination: fileIo.File | null = null
    const attachment: DraftAttachment = new DraftAttachment()
    attachment.storageName = Date.now().toString() + '-' + (DraftAttachmentStore.sequence++).toString() + '.bin'
    const target: string = DraftAttachmentStore.path(attachment.storageName)
    try {
      source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
      const stat: fileIo.Stat = await fileIo.stat(source.fd)
      if (stat.size > 10 * 1024 * 1024) {
        throw new Error('ATTACHMENT_TOO_LARGE')
      }
      destination = await fileIo.open(target, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      await fileIo.copyFile(source.fd, destination.fd)
      await fileIo.fsync(destination.fd)
      const copied: fileIo.Stat = await fileIo.stat(destination.fd)
      if (copied.size !== stat.size) {
        throw new Error('Attachment copy incomplete')
      }
      attachment.size = copied.size
      attachment.filename = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1))
      return attachment
    } catch (err) {
      DraftAttachmentStore.removeUnused([attachment], [])
      throw new Error(err instanceof Error ? err.message : 'Attachment copy failed')
    } finally {
      DraftAttachmentStore.closeSafely(source)
      DraftAttachmentStore.closeSafely(destination)
    }
  }

  static async readForSending(items: DraftAttachment[]): Promise<MailAttachment[]> {
    const result: MailAttachment[] = []
    for (let index = 0; index < items.length; index++) {
      const item: DraftAttachment = items[index]
      let file: fileIo.File | null = null
      try {
        file = await fileIo.open(DraftAttachmentStore.path(item.storageName), fileIo.OpenMode.READ_ONLY)
        const stat: fileIo.Stat = await fileIo.stat(file.fd)
        if (stat.size !== item.size || stat.size > 10 * 1024 * 1024) {
          throw new Error('Attachment changed')
        }
        const bytes: Uint8Array = new Uint8Array(stat.size)
        let offset: number = 0
        while (offset < stat.size) {
          const chunk: ArrayBuffer = new ArrayBuffer(Math.min(256 * 1024, stat.size - offset))
          const length: number = await fileIo.read(file.fd, chunk, { offset: offset })
          if (length <= 0) {
            throw new Error('Attachment read incomplete')
          }
          bytes.set(new Uint8Array(chunk, 0, length), offset)
          offset += length
        }
        const content: string = await new util.Base64Helper().encodeToString(bytes, util.Type.BASIC)
        result.push(new MailAttachment(item.filename, content, item.type))
      } finally {
        DraftAttachmentStore.closeSafely(file)
      }
    }
    return result
  }

  static removeUnused(previous: DraftAttachment[], retained: DraftAttachment[]): void {
    for (let index = 0; index < previous.length; index++) {
      const item: DraftAttachment = previous[index]
      if (retained.some((current: DraftAttachment): boolean => current.storageName === item.storageName)) {
        continue
      }
      try {
        const path: string = DraftAttachmentStore.path(item.storageName)
        if (fileIo.accessSync(path)) {
          fileIo.unlinkSync(path)
        }
      } catch (err) {
        console.error('Draft attachment cleanup deferred')
      }
    }
  }

  private static path(name: string): string {
    if (DraftAttachmentStore.directory === '' || !/^[0-9]+-[0-9]+\.bin$/.test(name)) {
      throw new Error('Invalid draft attachment path')
    }
    return DraftAttachmentStore.directory + '/' + name
  }

  private static closeSafely(file: fileIo.File | null): void {
    if (file === null) { return }
    try {
      fileIo.closeSync(file)
    } catch (err) {
      console.error('Draft attachment file close failed')
    }
  }
}
