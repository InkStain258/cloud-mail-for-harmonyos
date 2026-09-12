import { MailItem } from './MailModels'

// Memory-only: no mail body is written into preferences, logs, or shared backup storage.
export class MailDetailCache {
  private static scope: string = ''
  private static entries: MailItem[] = []
  private static bytes: number = 0
  private static readonly MAX_ITEMS: number = 32
  private static readonly MAX_BYTES: number = 8 * 1024 * 1024

  static selectScope(scope: string): void {
    if (MailDetailCache.scope !== scope) {
      MailDetailCache.clear()
      MailDetailCache.scope = scope
    }
  }

  static clear(): void {
    MailDetailCache.entries = []
    MailDetailCache.bytes = 0
    MailDetailCache.scope = ''
  }

  static get(id: number): MailItem | null {
    const index: number = MailDetailCache.entries.findIndex((item: MailItem) => item.id === id)
    if (index < 0) { return null }
    const item: MailItem = MailDetailCache.entries[index]
    MailDetailCache.entries.splice(index, 1)
    MailDetailCache.entries.push(item)
    return item.copy()
  }

  static remove(id: number): void {
    const index: number = MailDetailCache.entries.findIndex((item: MailItem) => item.id === id)
    if (index >= 0) {
      MailDetailCache.bytes -= MailDetailCache.size(MailDetailCache.entries[index])
      MailDetailCache.entries.splice(index, 1)
    }
  }

  static put(item: MailItem): void {
    if (!item.detailLoaded) { return }
    MailDetailCache.remove(item.id)
    const bytes: number = MailDetailCache.size(item)
    if (bytes > MailDetailCache.MAX_BYTES) { return }
    while (MailDetailCache.entries.length > 0 &&
      (MailDetailCache.entries.length >= MailDetailCache.MAX_ITEMS || MailDetailCache.bytes + bytes > MailDetailCache.MAX_BYTES)) {
      MailDetailCache.remove(MailDetailCache.entries[0].id)
    }
    MailDetailCache.entries.push(item.copy())
    MailDetailCache.bytes += bytes
  }

  private static size(item: MailItem): number {
    return JSON.stringify(item).length * 2
  }
}
