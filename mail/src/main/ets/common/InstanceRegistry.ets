import { preferences } from '@kit.ArkData'

import Constants from './Constants'
import { MailInstance, MailInstancePayload } from './InstanceModels'

export class InstanceRegistry {
  private static readonly DEFAULT_INSTANCE_ID: string = 'riordon-cloud-mail'
  private static registryPreferences: preferences.Preferences | null = null
  private static instances: MailInstance[] = []
  private static activeInstanceId: string = InstanceRegistry.DEFAULT_INSTANCE_ID

  static initialize(context: Context): void {
    try {
      InstanceRegistry.registryPreferences = preferences.getPreferencesSync(context, { name: 'cloud_mail_instances' })
      const storedInstances: string = InstanceRegistry.registryPreferences.getSync('instances', '') as string
      InstanceRegistry.activeInstanceId = InstanceRegistry.registryPreferences.getSync(
        'activeInstanceId', InstanceRegistry.DEFAULT_INSTANCE_ID) as string
      InstanceRegistry.instances = InstanceRegistry.parseInstances(storedInstances)
    } catch (err) {
      console.error('initialize instance registry failed')
      InstanceRegistry.instances = []
      InstanceRegistry.activeInstanceId = InstanceRegistry.DEFAULT_INSTANCE_ID
    }
    InstanceRegistry.ensureDefaultInstance()
    if (InstanceRegistry.find(InstanceRegistry.activeInstanceId) === null) {
      InstanceRegistry.activeInstanceId = InstanceRegistry.DEFAULT_INSTANCE_ID
    }
    InstanceRegistry.persist()
  }

  static getDefaultInstanceId(): string {
    return InstanceRegistry.DEFAULT_INSTANCE_ID
  }

  static getActiveInstanceId(): string {
    return InstanceRegistry.activeInstanceId
  }

  static getActiveInstance(): MailInstance {
    const instance: MailInstance | null = InstanceRegistry.find(InstanceRegistry.activeInstanceId)
    if (instance !== null) {
      return instance
    }
    return InstanceRegistry.createDefaultInstance()
  }

  static getInstances(): MailInstance[] {
    const result: MailInstance[] = []
    for (let index = 0; index < InstanceRegistry.instances.length; index++) {
      result.push(InstanceRegistry.instances[index])
    }
    return result
  }

  static find(instanceId: string): MailInstance | null {
    for (let index = 0; index < InstanceRegistry.instances.length; index++) {
      if (InstanceRegistry.instances[index].instanceId === instanceId) {
        return InstanceRegistry.instances[index]
      }
    }
    return null
  }

  static save(instance: MailInstance): void {
    let replaced: boolean = false
    for (let index = 0; index < InstanceRegistry.instances.length; index++) {
      if (InstanceRegistry.instances[index].instanceId === instance.instanceId) {
        InstanceRegistry.instances[index] = instance
        replaced = true
        break
      }
    }
    if (!replaced) {
      InstanceRegistry.instances.push(instance)
    }
    InstanceRegistry.persist()
  }

  static updateSession(instanceId: string, email: string, role: string, roleName: string,
    accountId: number, instanceRole: string = ''): void {
    const instance: MailInstance | null = InstanceRegistry.find(instanceId)
    if (instance === null) {
      return
    }
    instance.localEmail = email
    instance.localRole = role
    instance.localRoleName = roleName
    instance.accountId = accountId
    if (instanceRole !== '') {
      instance.instanceRole = instanceRole
    }
    InstanceRegistry.save(instance)
  }

  static updateMetadata(instanceId: string, displayName: string, apiBaseUrl: string = '',
    originHost: string = ''): boolean {
    const instance: MailInstance | null = InstanceRegistry.find(instanceId)
    if (instance === null) {
      return false
    }
    let changed: boolean = false
    if (displayName !== '' && instance.displayName !== displayName) {
      instance.displayName = displayName
      changed = true
    }
    if (apiBaseUrl !== '' && instance.apiBaseUrl !== apiBaseUrl) {
      instance.apiBaseUrl = apiBaseUrl
      changed = true
    }
    if (originHost !== '' && instance.originHost !== originHost) {
      instance.originHost = originHost
      changed = true
    }
    if (changed) {
      InstanceRegistry.persist()
    }
    return changed
  }

  static setActiveInstance(instanceId: string): boolean {
    if (InstanceRegistry.find(instanceId) === null) {
      return false
    }
    InstanceRegistry.activeInstanceId = instanceId
    InstanceRegistry.persist()
    return true
  }

  static remove(instanceId: string): boolean {
    if (instanceId === InstanceRegistry.DEFAULT_INSTANCE_ID) {
      return false
    }
    const next: MailInstance[] = []
    let removed: boolean = false
    for (let index = 0; index < InstanceRegistry.instances.length; index++) {
      if (InstanceRegistry.instances[index].instanceId === instanceId) {
        removed = true
      } else {
        next.push(InstanceRegistry.instances[index])
      }
    }
    if (!removed) {
      return false
    }
    InstanceRegistry.instances = next
    if (InstanceRegistry.activeInstanceId === instanceId) {
      InstanceRegistry.activeInstanceId = InstanceRegistry.DEFAULT_INSTANCE_ID
    }
    InstanceRegistry.persist()
    return true
  }

  private static ensureDefaultInstance(): void {
    if (InstanceRegistry.find(InstanceRegistry.DEFAULT_INSTANCE_ID) !== null) {
      return
    }
    InstanceRegistry.instances.unshift(InstanceRegistry.createDefaultInstance())
  }

  private static createDefaultInstance(): MailInstance {
    return new MailInstance(
      InstanceRegistry.DEFAULT_INSTANCE_ID,
      'inkstain 邮箱',
      Constants.API_URL,
      'mail.inkstain.top'
    )
  }

  private static parseInstances(value: string): MailInstance[] {
    if (value === '') {
      return []
    }
    try {
      const payloads: MailInstancePayload[] = JSON.parse(value) as MailInstancePayload[]
      const result: MailInstance[] = []
      for (let index = 0; index < payloads.length; index++) {
        const instance: MailInstance = MailInstance.fromPayload(payloads[index])
        if (instance.instanceId !== '' && instance.apiBaseUrl !== '') {
          result.push(instance)
        }
      }
      return result
    } catch (err) {
      console.error('parse instance registry failed')
      return []
    }
  }

  private static persist(): void {
    if (InstanceRegistry.registryPreferences === null) {
      return
    }
    try {
      InstanceRegistry.registryPreferences.putSync('instances', JSON.stringify(InstanceRegistry.instances))
      InstanceRegistry.registryPreferences.putSync('activeInstanceId', InstanceRegistry.activeInstanceId)
      InstanceRegistry.registryPreferences.flushSync()
    } catch (err) {
      console.error('persist instance registry failed')
    }
  }
}
