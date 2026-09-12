import { ApiResponse, HttpClient } from './HttpClient'
import { SessionService } from './SessionService'

export class NativeCapabilityInfo {
  summaryDetail: boolean = false
  purposeAddresses: boolean = false
}

export class NativeCapabilities {
  private static scope: string = ''
  private static expiresAt: number = 0
  private static value: NativeCapabilityInfo = new NativeCapabilityInfo()
  private static pending: Promise<NativeCapabilityInfo> | null = null

  static sessionKey(): string {
    return SessionService.getActiveInstanceId() + '|' + SessionService.getApiBaseUrl() + '|' +
      (AppStorage.get<string>('authEmail') || '') + '|' + (AppStorage.get<number>('sessionRevision') || 0).toString()
  }

  static async current(forceRefresh: boolean = false): Promise<NativeCapabilityInfo> {
    const scope: string = NativeCapabilities.sessionKey()
    if (NativeCapabilities.scope === scope) {
      if (NativeCapabilities.pending !== null) { return NativeCapabilities.pending }
      if (!forceRefresh && Date.now() < NativeCapabilities.expiresAt) { return NativeCapabilities.value }
    }
    NativeCapabilities.scope = scope
    NativeCapabilities.value = new NativeCapabilityInfo()
    const pending: Promise<NativeCapabilityInfo> = NativeCapabilities.fetch(scope)
    NativeCapabilities.pending = pending
    return pending
  }

  private static async fetch(scope: string): Promise<NativeCapabilityInfo> {
    const value: NativeCapabilityInfo = new NativeCapabilityInfo()
    let ttl: number = 60000
    try {
      const response: ApiResponse = await HttpClient.get('/native/capabilities')
      const remote: NativeCapabilityInfo | null = response.data as NativeCapabilityInfo | null
      if (remote !== null) {
        value.summaryDetail = remote.summaryDetail === true
        value.purposeAddresses = remote.purposeAddresses === true
      }
      ttl = 300000
    } catch (err) {
      // Old instances need no deployment or schema changes. Do not infer support from version strings.
    }
    if (scope !== NativeCapabilities.sessionKey()) { return new NativeCapabilityInfo() }
    NativeCapabilities.value = value
    NativeCapabilities.expiresAt = Date.now() + ttl
    NativeCapabilities.pending = null
    return value
  }
}
