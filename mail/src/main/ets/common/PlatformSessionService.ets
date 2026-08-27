import { preferences } from '@kit.ArkData'

import { PlatformLoginPayload, PlatformUser } from './InstanceModels'
import { SecureTokenStore } from './SecureTokenStore'

export class PlatformSessionService {
  private static platformPreferences: preferences.Preferences | null = null

  static initialize(context: Context): void {
    let role: string = 'MEMBER'
    let nickName: string = ''
    let avatarUrl: string = ''
    let huaweiUserId: string = ''
    try {
      PlatformSessionService.platformPreferences = preferences.getPreferencesSync(
        context, { name: 'cloud_mail_platform' })
      role = PlatformSessionService.platformPreferences.getSync('role', 'MEMBER') as string
      nickName = PlatformSessionService.platformPreferences.getSync('nickName', '') as string
      avatarUrl = PlatformSessionService.platformPreferences.getSync('avatarUrl', '') as string
      huaweiUserId = PlatformSessionService.platformPreferences.getSync('huaweiUserId', '') as string
    } catch (err) {
      console.error('initialize platform session failed')
    }
    AppStorage.setOrCreate('platformToken', SecureTokenStore.getPlatformToken())
    AppStorage.setOrCreate('platformRole', role)
    AppStorage.setOrCreate('platformNickName', nickName)
    AppStorage.setOrCreate('platformAvatarUrl', avatarUrl)
    AppStorage.setOrCreate('platformHuaweiUserId', huaweiUserId)
    AppStorage.setOrCreate('platformRevision', 0)
  }

  static save(payload: PlatformLoginPayload): void {
    SecureTokenStore.savePlatformToken(payload.token)
    PlatformSessionService.applyUser(payload.user)
    AppStorage.set('platformToken', payload.token)
    PlatformSessionService.notifyChanged()
  }

  static clear(): void {
    SecureTokenStore.removePlatformToken()
    AppStorage.set('platformToken', '')
    AppStorage.set('platformRole', 'MEMBER')
    AppStorage.set('platformNickName', '')
    AppStorage.set('platformAvatarUrl', '')
    AppStorage.set('platformHuaweiUserId', '')
    PlatformSessionService.notifyChanged()
    if (PlatformSessionService.platformPreferences === null) {
      return
    }
    try {
      PlatformSessionService.platformPreferences.clearSync()
      PlatformSessionService.platformPreferences.flushSync()
    } catch (err) {
      console.error('clear platform session failed')
    }
  }

  static getToken(): string {
    const value: string | undefined = AppStorage.get('platformToken') as string | undefined
    return value === undefined ? '' : value
  }

  static getRole(): string {
    const value: string | undefined = AppStorage.get('platformRole') as string | undefined
    return value === undefined ? 'MEMBER' : value
  }

  static getNickName(): string {
    const value: string | undefined = AppStorage.get('platformNickName') as string | undefined
    return value === undefined ? '' : value
  }

  static getAvatarUrl(): string {
    const value: string | undefined = AppStorage.get('platformAvatarUrl') as string | undefined
    return value === undefined ? '' : value
  }

  static getHuaweiUserId(): string {
    const value: string | undefined = AppStorage.get('platformHuaweiUserId') as string | undefined
    return value === undefined ? '' : value
  }

  private static applyUser(user: PlatformUser): void {
    AppStorage.set('platformRole', user.platformRole)
    AppStorage.set('platformNickName', user.nickName)
    AppStorage.set('platformAvatarUrl', user.avatarUrl)
    AppStorage.set('platformHuaweiUserId', user.huaweiUserId)
    if (PlatformSessionService.platformPreferences === null) {
      return
    }
    try {
      PlatformSessionService.platformPreferences.putSync('role', user.platformRole)
      PlatformSessionService.platformPreferences.putSync('nickName', user.nickName)
      PlatformSessionService.platformPreferences.putSync('avatarUrl', user.avatarUrl)
      PlatformSessionService.platformPreferences.putSync('huaweiUserId', user.huaweiUserId)
      PlatformSessionService.platformPreferences.flushSync()
    } catch (err) {
      console.error('save platform profile failed')
    }
  }

  private static notifyChanged(): void {
    const revision: number | undefined = AppStorage.get('platformRevision') as number | undefined
    AppStorage.set('platformRevision', revision === undefined ? 1 : revision + 1)
  }
}
