import { MailItem } from './MailModels'
import { MailPage, MailService } from './MailService'
import { SessionService } from './SessionService'

export enum MailHistoryKind {
  Inbox,
  Sent,
  Starred
}

// The cursor and in-flight generation belong to one instance/session. A cancelled
// or old-session response must never replace data for the newly selected account.
export class MailHistoryLoader {
  items: MailItem[] = []
  total: number = -1
  hasMore: boolean = true
  stalled: boolean = false
  loading: boolean = false
  private cursor: number = 0
  private generation: number = 0
  private scope: string = ''
  private kind: MailHistoryKind
  private requireFullBodies: boolean = false

  constructor(kind: MailHistoryKind) {
    this.kind = kind
  }

  static sessionKey(): string {
    const email: string = AppStorage.get<string>('authEmail') || ''
    const revision: number = AppStorage.get<number>('sessionRevision') || 0
    return SessionService.getActiveInstanceId() + '|' + SessionService.getApiBaseUrl() + '|' + email + '|' + revision
  }

  reset(requireFullBodies: boolean = false): void {
    this.cancel()
    this.scope = MailHistoryLoader.sessionKey()
    this.requireFullBodies = requireFullBodies
    this.items = []
    this.total = -1
    this.cursor = 0
    this.hasMore = true
    this.stalled = false
  }

  cancel(): void {
    this.generation++
    this.loading = false
  }

  replaceItems(items: MailItem[]): void {
    if (this.cursor === 0 && this.loading) {
      return
    }
    this.items = items.slice()
  }

  async loadNext(): Promise<boolean> {
    if (this.loading || !this.hasMore || this.scope !== MailHistoryLoader.sessionKey()) {
      return false
    }
    const generation: number = this.generation
    this.loading = true
    try {
      const page: MailPage = await this.fetchPage()
      if (generation !== this.generation || this.scope !== MailHistoryLoader.sessionKey()) {
        return false
      }
      const seen: Set<number> = new Set<number>()
      this.items.forEach((item: MailItem) => { seen.add(item.id) })
      const merged: MailItem[] = this.items.slice()
      page.items.forEach((item: MailItem) => {
        if (!seen.has(item.id)) {
          seen.add(item.id)
          merged.push(item)
        }
      })
      this.stalled = page.items.length > 0 && (page.nextCursor <= 0 ||
        (this.cursor > 0 && page.nextCursor >= this.cursor) || merged.length === this.items.length)
      if (page.hasMore && page.items.length === 0) {
        this.stalled = true
      }
      this.items = merged
      this.total = page.total
      this.cursor = page.nextCursor
      this.hasMore = page.hasMore && !this.stalled
      return true
    } catch (err) {
      if (generation === this.generation && this.scope === MailHistoryLoader.sessionKey()) {
        const requestError: Error = err as Error
        throw requestError
      }
      return false
    } finally {
      if (generation === this.generation) {
        this.loading = false
      }
    }
  }

  private async fetchPage(): Promise<MailPage> {
    if (this.kind === MailHistoryKind.Sent) {
      return MailService.loadSentPage(this.cursor)
    }
    if (this.kind === MailHistoryKind.Starred) {
      return MailService.loadStarredPage(this.cursor)
    }
    return MailService.loadInboxPage(this.cursor, this.requireFullBodies)
  }
}
