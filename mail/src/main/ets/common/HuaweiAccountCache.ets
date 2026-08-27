import { preferences } from '@kit.ArkData'
import { HuaweiAccountBinding } from '../api/HuaweiAccountApi'

export class HuaweiAccountCache {
  private static readonly CACHE_NAME: string = 'cloud_mail_huawei_account'
  private static cachePreferences: preferences.Preferences | null = null
  private static refreshedEmails: string[] = []

  static load(context: Context, ownerEmail: string): HuaweiAccountBinding | null {
    try {
      const cache: preferences.Preferences | null = HuaweiAccountCache.getPreferences(context)
      if (cache === null) {
        return null
      }
      const cachedOwner: string = cache.getSync('ownerEmail', '') as string
      if (ownerEmail === '' || cachedOwner !== ownerEmail) {
        return null
      }
      return HuaweiAccountBinding.fromCache(
        cache.getSync('huaweiUserId', '') as string,
        cache.getSync('nickName', '') as string,
        cache.getSync('avatarUrl', '') as string,
        cache.getSync('primaryEmail', '') as string,
        cache.getSync('profileUpdateTime', '') as string,
        cache.getSync('createTime', '') as string,
        cache.getSync('userCreateTime', '') as string,
        cache.getSync('receiveCount', 0) as number,
        cache.getSync('sentCount', 0) as number,
        cache.getSync('starCount', 0) as number
      )
    } catch (err) {
      console.error('load Huawei account cache failed')
      return null
    }
  }

  static save(context: Context, ownerEmail: string, binding: HuaweiAccountBinding): void {
    try {
      const cache: preferences.Preferences | null = HuaweiAccountCache.getPreferences(context)
      if (cache === null) {
        return
      }
      cache.putSync('ownerEmail', ownerEmail)
      cache.putSync('huaweiUserId', binding.huaweiUserId)
      cache.putSync('nickName', binding.nickName)
      cache.putSync('avatarUrl', binding.avatarUrl)
      cache.putSync('primaryEmail', binding.primaryEmail)
      cache.putSync('profileUpdateTime', binding.profileUpdateTime)
      cache.putSync('createTime', binding.createTime)
      cache.putSync('userCreateTime', binding.userCreateTime)
      cache.putSync('receiveCount', binding.receiveCount)
      cache.putSync('sentCount', binding.sentCount)
      cache.putSync('starCount', binding.starCount)
      cache.flushSync()
    } catch (err) {
      console.error('save Huawei account cache failed')
    }
  }

  static clear(context: Context, ownerEmail: string): void {
    try {
      const cache: preferences.Preferences | null = HuaweiAccountCache.getPreferences(context)
      if (cache === null) {
        return
      }
      if ((cache.getSync('ownerEmail', '') as string) !== ownerEmail) {
        return
      }
      cache.clearSync()
      cache.flushSync()
    } catch (err) {
      console.error('clear Huawei account cache failed')
    }
  }

  static shouldRefresh(ownerEmail: string): boolean {
    return ownerEmail !== '' && HuaweiAccountCache.refreshedEmails.indexOf(ownerEmail) < 0
  }

  static markRefreshed(ownerEmail: string): void {
    if (ownerEmail !== '' && HuaweiAccountCache.refreshedEmails.indexOf(ownerEmail) < 0) {
      HuaweiAccountCache.refreshedEmails.push(ownerEmail)
    }
  }

  private static getPreferences(context: Context): preferences.Preferences | null {
    if (HuaweiAccountCache.cachePreferences === null) {
      try {
        HuaweiAccountCache.cachePreferences =
          preferences.getPreferencesSync(context, { name: HuaweiAccountCache.CACHE_NAME })
      } catch (err) {
        console.error('open Huawei account cache failed')
        return null
      }
    }
    return HuaweiAccountCache.cachePreferences
  }
}
