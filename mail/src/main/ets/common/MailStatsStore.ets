import { InstanceRegistry } from './InstanceRegistry'

export class MailStatsStore {
  private static readonly OWNER_KEY: string = 'mailStatsOwnerEmail'
  private static readonly RECEIVE_KEY: string = 'mailReceiveCount'
  private static readonly SENT_KEY: string = 'mailSentCount'
  private static readonly STAR_KEY: string = 'mailStarCount'
  private static readonly RECEIVE_READY_KEY: string = 'mailReceiveCountReady'
  private static readonly SENT_READY_KEY: string = 'mailSentCountReady'
  private static readonly STAR_READY_KEY: string = 'mailStarCountReady'

  static initialize(): void {
    AppStorage.setOrCreate(MailStatsStore.OWNER_KEY, '')
    AppStorage.setOrCreate(MailStatsStore.RECEIVE_KEY, 0)
    AppStorage.setOrCreate(MailStatsStore.SENT_KEY, 0)
    AppStorage.setOrCreate(MailStatsStore.STAR_KEY, 0)
    AppStorage.setOrCreate(MailStatsStore.RECEIVE_READY_KEY, false)
    AppStorage.setOrCreate(MailStatsStore.SENT_READY_KEY, false)
    AppStorage.setOrCreate(MailStatsStore.STAR_READY_KEY, false)
    MailStatsStore.setOwner(MailStatsStore.getCurrentEmail())
  }

  static setOwner(ownerEmail: string): void {
    const currentOwner: string = MailStatsStore.getString(MailStatsStore.OWNER_KEY)
    const ownerKey: string = ownerEmail === '' ? '' : InstanceRegistry.getActiveInstanceId() + '|' + ownerEmail
    if (currentOwner === ownerKey) {
      return
    }
    MailStatsStore.setString(MailStatsStore.OWNER_KEY, ownerKey)
    MailStatsStore.resetCounts()
  }

  static reset(): void {
    MailStatsStore.setString(MailStatsStore.OWNER_KEY, '')
    MailStatsStore.resetCounts()
  }

  static hasCurrentStats(): boolean {
    MailStatsStore.ensureCurrentOwner()
    return MailStatsStore.getBoolean(MailStatsStore.RECEIVE_READY_KEY) &&
      MailStatsStore.getBoolean(MailStatsStore.SENT_READY_KEY) &&
      MailStatsStore.getBoolean(MailStatsStore.STAR_READY_KEY)
  }

  static syncMissing(receiveCount: number, sentCount: number, starCount: number): void {
    MailStatsStore.ensureCurrentOwner()
    if (!MailStatsStore.getBoolean(MailStatsStore.RECEIVE_READY_KEY)) {
      MailStatsStore.setCount(MailStatsStore.RECEIVE_KEY, receiveCount)
      MailStatsStore.setBoolean(MailStatsStore.RECEIVE_READY_KEY, true)
    }
    if (!MailStatsStore.getBoolean(MailStatsStore.SENT_READY_KEY)) {
      MailStatsStore.setCount(MailStatsStore.SENT_KEY, sentCount)
      MailStatsStore.setBoolean(MailStatsStore.SENT_READY_KEY, true)
    }
    if (!MailStatsStore.getBoolean(MailStatsStore.STAR_READY_KEY)) {
      MailStatsStore.setCount(MailStatsStore.STAR_KEY, starCount)
      MailStatsStore.setBoolean(MailStatsStore.STAR_READY_KEY, true)
    }
  }

  static sync(receiveCount: number, sentCount: number, starCount: number): void {
    MailStatsStore.ensureCurrentOwner()
    MailStatsStore.setCount(MailStatsStore.RECEIVE_KEY, receiveCount)
    MailStatsStore.setCount(MailStatsStore.SENT_KEY, sentCount)
    MailStatsStore.setCount(MailStatsStore.STAR_KEY, starCount)
    MailStatsStore.setBoolean(MailStatsStore.RECEIVE_READY_KEY, true)
    MailStatsStore.setBoolean(MailStatsStore.SENT_READY_KEY, true)
    MailStatsStore.setBoolean(MailStatsStore.STAR_READY_KEY, true)
  }

  static syncReceive(receiveCount: number): void {
    MailStatsStore.ensureCurrentOwner()
    MailStatsStore.setCount(MailStatsStore.RECEIVE_KEY, receiveCount)
    MailStatsStore.setBoolean(MailStatsStore.RECEIVE_READY_KEY, true)
  }

  static syncSent(sentCount: number): void {
    MailStatsStore.ensureCurrentOwner()
    MailStatsStore.setCount(MailStatsStore.SENT_KEY, sentCount)
    MailStatsStore.setBoolean(MailStatsStore.SENT_READY_KEY, true)
  }

  static syncStar(starCount: number): void {
    MailStatsStore.ensureCurrentOwner()
    MailStatsStore.setCount(MailStatsStore.STAR_KEY, starCount)
    MailStatsStore.setBoolean(MailStatsStore.STAR_READY_KEY, true)
  }

  static incrementSent(): void {
    MailStatsStore.ensureCurrentOwner()
    // A delta cannot establish an unknown total for an external instance.
    if (!MailStatsStore.getBoolean(MailStatsStore.SENT_READY_KEY)) {
      return
    }
    MailStatsStore.setCount(MailStatsStore.SENT_KEY, MailStatsStore.getCount(MailStatsStore.SENT_KEY) + 1)
  }

  static adjustStar(delta: number): void {
    MailStatsStore.ensureCurrentOwner()
    if (!MailStatsStore.getBoolean(MailStatsStore.STAR_READY_KEY)) {
      return
    }
    MailStatsStore.setCount(MailStatsStore.STAR_KEY, MailStatsStore.getCount(MailStatsStore.STAR_KEY) + delta)
  }

  private static ensureCurrentOwner(): void {
    MailStatsStore.setOwner(MailStatsStore.getCurrentEmail())
  }

  private static getCurrentEmail(): string {
    const ownerEmail: string | undefined = AppStorage.get('authEmail') as string | undefined
    return ownerEmail === undefined ? '' : ownerEmail
  }

  private static resetCounts(): void {
    MailStatsStore.setCount(MailStatsStore.RECEIVE_KEY, 0)
    MailStatsStore.setCount(MailStatsStore.SENT_KEY, 0)
    MailStatsStore.setCount(MailStatsStore.STAR_KEY, 0)
    MailStatsStore.setBoolean(MailStatsStore.RECEIVE_READY_KEY, false)
    MailStatsStore.setBoolean(MailStatsStore.SENT_READY_KEY, false)
    MailStatsStore.setBoolean(MailStatsStore.STAR_READY_KEY, false)
  }

  private static getCount(key: string): number {
    const value: number | undefined = AppStorage.get(key) as number | undefined
    return value === undefined ? 0 : value
  }

  private static setCount(key: string, value: number): void {
    AppStorage.set(key, Math.max(0, Math.floor(value)))
  }

  private static getString(key: string): string {
    const value: string | undefined = AppStorage.get(key) as string | undefined
    return value === undefined ? '' : value
  }

  private static setString(key: string, value: string): void {
    AppStorage.set(key, value)
  }

  private static getBoolean(key: string): boolean {
    const value: boolean | undefined = AppStorage.get(key) as boolean | undefined
    return value === undefined ? false : value
  }

  private static setBoolean(key: string, value: boolean): void {
    AppStorage.set(key, value)
  }
}
