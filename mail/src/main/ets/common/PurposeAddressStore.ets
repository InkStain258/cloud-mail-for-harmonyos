import { preferences } from '@kit.ArkData'
import { SessionService } from './SessionService'
import { PurposeAddressEntry, PurposeAddressRules } from './PurposeAddressRules'

export class PurposeAddressScope {
  instanceId: string = ''
  apiBaseUrl: string = ''
  ownerEmail: string = ''
  ownerAccountId: number = 0
  baseEmail: string = ''
  revision: number = 0
}

export class PurposeAddressStore {
  static capture(baseEmail: string): PurposeAddressScope {
    const scope: PurposeAddressScope = new PurposeAddressScope()
    scope.instanceId = SessionService.getActiveInstanceId()
    scope.apiBaseUrl = SessionService.getApiBaseUrl()
    scope.ownerEmail = (AppStorage.get('authEmail') as string | undefined) || ''
    scope.ownerAccountId = (AppStorage.get('currentAccountId') as number | undefined) || 0
    scope.baseEmail = baseEmail
    scope.revision = (AppStorage.get('sessionRevision') as number | undefined) || 0
    return scope
  }

  static isCurrent(scope: PurposeAddressScope): boolean {
    const current: PurposeAddressScope = PurposeAddressStore.capture(scope.baseEmail)
    return scope.instanceId !== '' && scope.ownerEmail !== '' &&
      ((AppStorage.get('authToken') as string | undefined) || '') !== '' &&
      scope.instanceId === current.instanceId && scope.apiBaseUrl === current.apiBaseUrl &&
      scope.ownerEmail === current.ownerEmail && scope.ownerAccountId === current.ownerAccountId &&
      scope.revision === current.revision
  }

  static load(context: Context, scope: PurposeAddressScope): PurposeAddressEntry[] {
    PurposeAddressStore.requireCurrent(scope)
    const store: preferences.Preferences = PurposeAddressStore.open(context)
    const raw: string = store.getSync(PurposeAddressStore.key(scope), '[]') as string
    return PurposeAddressRules.parse(raw, scope.baseEmail)
  }

  static add(context: Context, scope: PurposeAddressScope, tag: string, label: string): PurposeAddressEntry[] {
    const entries: PurposeAddressEntry[] = PurposeAddressStore.load(context, scope)
    const entry: PurposeAddressEntry = PurposeAddressRules.create(scope.baseEmail, tag, label)
    if (entries.some((item: PurposeAddressEntry): boolean => item.tag === entry.tag)) {
      throw new Error('purpose_duplicate')
    }
    if (entries.length >= PurposeAddressRules.LIMIT) {
      throw new Error('purpose_limit')
    }
    entries.unshift(entry)
    PurposeAddressStore.save(context, scope, entries)
    return entries
  }

  static remove(context: Context, scope: PurposeAddressScope, tag: string): PurposeAddressEntry[] {
    const entries: PurposeAddressEntry[] = PurposeAddressStore.load(context, scope)
      .filter((item: PurposeAddressEntry): boolean => item.tag !== tag)
    PurposeAddressStore.save(context, scope, entries)
    return entries
  }

  private static save(context: Context, scope: PurposeAddressScope, entries: PurposeAddressEntry[]): void {
    PurposeAddressStore.requireCurrent(scope)
    const store: preferences.Preferences = PurposeAddressStore.open(context)
    const key: string = PurposeAddressStore.key(scope)
    const previous: string = store.getSync(key, '[]') as string
    try {
      store.putSync(key, JSON.stringify(entries))
      store.flushSync()
    } catch (err) {
      // Keep the in-memory preference consistent with the last acknowledged save.
      store.putSync(key, previous)
      throw new Error('purpose_storage_failed')
    }
  }

  private static key(scope: PurposeAddressScope): string {
    const key: string = 'v1.' + encodeURIComponent(JSON.stringify([
      scope.instanceId, scope.apiBaseUrl, scope.ownerEmail, scope.ownerAccountId.toString(), scope.baseEmail
    ]))
    if (key.length > 1024) {
      throw new Error('purpose_storage_failed')
    }
    return key
  }

  private static requireCurrent(scope: PurposeAddressScope): void {
    if (!PurposeAddressStore.isCurrent(scope)) {
      throw new Error('purpose_session_changed')
    }
  }

  private static open(context: Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: 'cloud_mail_purpose_addresses' })
  }
}
