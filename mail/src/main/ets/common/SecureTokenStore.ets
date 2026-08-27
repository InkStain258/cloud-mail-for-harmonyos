import { asset } from '@kit.AssetStoreKit'
import { util } from '@kit.ArkTS'

export class SecureTokenStore {
  private static readonly INSTANCE_PREFIX: string = 'cloudmail.instance.token.'
  private static readonly PLATFORM_ALIAS: string = 'cloudmail.platform.token'

  static saveInstanceToken(instanceId: string, token: string): void {
    SecureTokenStore.save(SecureTokenStore.INSTANCE_PREFIX + instanceId, token)
  }

  static getInstanceToken(instanceId: string): string {
    return SecureTokenStore.get(SecureTokenStore.INSTANCE_PREFIX + instanceId)
  }

  static removeInstanceToken(instanceId: string): void {
    SecureTokenStore.remove(SecureTokenStore.INSTANCE_PREFIX + instanceId)
  }

  static savePlatformToken(token: string): void {
    SecureTokenStore.save(SecureTokenStore.PLATFORM_ALIAS, token)
  }

  static getPlatformToken(): string {
    return SecureTokenStore.get(SecureTokenStore.PLATFORM_ALIAS)
  }

  static removePlatformToken(): void {
    SecureTokenStore.remove(SecureTokenStore.PLATFORM_ALIAS)
  }

  private static save(alias: string, secret: string): void {
    if (alias === '' || secret === '') {
      return
    }
    const query: asset.AssetMap = new Map()
    query.set(asset.Tag.ALIAS, SecureTokenStore.toBytes(alias))
    const update: asset.AssetMap = new Map()
    update.set(asset.Tag.SECRET, SecureTokenStore.toBytes(secret))
    try {
      asset.updateSync(query, update)
      return
    } catch (err) {
      const attributes: asset.AssetMap = new Map()
      attributes.set(asset.Tag.ALIAS, SecureTokenStore.toBytes(alias))
      attributes.set(asset.Tag.SECRET, SecureTokenStore.toBytes(secret))
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED)
      try {
        asset.addSync(attributes)
      } catch (addError) {
        console.error('save secure token failed')
      }
    }
  }

  private static get(alias: string): string {
    const query: asset.AssetMap = new Map()
    query.set(asset.Tag.ALIAS, SecureTokenStore.toBytes(alias))
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
    try {
      const result: asset.AssetMap[] = asset.querySync(query)
      if (result.length === 0) {
        return ''
      }
      const secret: Uint8Array = result[0].get(asset.Tag.SECRET) as Uint8Array
      return SecureTokenStore.fromBytes(secret)
    } catch (err) {
      return ''
    }
  }

  private static remove(alias: string): void {
    const query: asset.AssetMap = new Map()
    query.set(asset.Tag.ALIAS, SecureTokenStore.toBytes(alias))
    try {
      asset.removeSync(query)
    } catch (err) {
      console.info('secure token already removed')
    }
  }

  private static toBytes(value: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder()
    return encoder.encodeInto(value)
  }

  private static fromBytes(value: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    return decoder.decodeToString(value, { stream: false })
  }
}
