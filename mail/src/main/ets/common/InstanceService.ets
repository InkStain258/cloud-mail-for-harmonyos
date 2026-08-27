import { PlatformApi } from '../api/PlatformApi'
import { AuthUserInfo } from '../api/AuthApi'
import { ApiException, ApiResponse } from './HttpClient'
import { ExternalHttpClient } from './ExternalHttpClient'
import { InstanceRegistry } from './InstanceRegistry'
import {
  MailInstance,
  PlatformAdminBindingPage,
  PlatformBinding,
  PlatformBindingPayload,
  PlatformImportResult,
  PlatformInstance,
  PlatformLoginPayload
} from './InstanceModels'
import { PlatformSessionService } from './PlatformSessionService'
import { SessionService } from './SessionService'

class InstanceLoginRequest {
  email: string
  password: string

  constructor(email: string, password: string) {
    this.email = email
    this.password = password
  }
}

class InstanceLoginPayload {
  token: string = ''
}

class InstanceRemoteAccount {
  accountId: number = 0
}

class InstanceRemoteRole {
  name: string = ''
}

class InstanceRemoteUser {
  email: string = ''
  account: InstanceRemoteAccount = new InstanceRemoteAccount()
  role: InstanceRemoteRole = new InstanceRemoteRole()
  permKeys: string[] = []
}

export class InstanceBindResult {
  success: boolean
  message: string
  instance: MailInstance | null

  constructor(success: boolean, message: string, instance: MailInstance | null = null) {
    this.success = success
    this.message = message
    this.instance = instance
  }
}

export class InstanceService {
  static initialize(context: Context): void {
    PlatformSessionService.initialize(context)
  }

  static async ensurePlatformSession(forceRefresh: boolean = false): Promise<boolean> {
    if (!forceRefresh && PlatformSessionService.getToken() !== '') {
      return true
    }
    if (forceRefresh) {
      PlatformSessionService.clear()
    }
    const defaultToken: string = SessionService.getInstanceToken(InstanceRegistry.getDefaultInstanceId())
    if (defaultToken === '') {
      return false
    }
    try {
      const payload: PlatformLoginPayload = await PlatformApi.loginThroughAnchor(defaultToken)
      PlatformSessionService.save(payload)
      return true
    } catch (err) {
      console.error('platform anchor login failed')
      return false
    }
  }

  static async loadPlatformInstances(): Promise<PlatformInstance[]> {
    const instances: PlatformInstance[] = await InstanceService.withPlatformSession(
      (token: string): Promise<PlatformInstance[]> => {
      return PlatformApi.instances(token)
    })
    SessionService.synchronizeInstanceMetadata(instances)
    return instances
  }

  static async loadMyBindings(): Promise<PlatformBinding[]> {
    return InstanceService.withPlatformSession((token: string): Promise<PlatformBinding[]> => {
      return PlatformApi.myBindings(token)
    })
  }

  static async loadAdminBindings(keyword: string, page: number, size: number):
    Promise<PlatformAdminBindingPage> {
    return InstanceService.withPlatformSession((token: string): Promise<PlatformAdminBindingPage> => {
      return PlatformApi.adminBindings(token, keyword, page, size)
    })
  }

  static async createPlatformInstance(apiBaseUrl: string, displayName: string): Promise<void> {
    await InstanceService.withPlatformSession((token: string): Promise<Object> => {
      return PlatformApi.createInstance(token, apiBaseUrl, displayName)
    })
  }

  static async renamePlatformInstance(instanceId: string, displayName: string): Promise<void> {
    const normalizedName: string = displayName.trim()
    if (instanceId === '' || normalizedName === '') {
      throw new ApiException(400, '请输入有效的邮箱服务名称', false)
    }
    await InstanceService.withPlatformSession((token: string): Promise<void> => {
      return PlatformApi.renameInstance(token, instanceId, normalizedName)
    })
    SessionService.updateInstanceMetadata(instanceId, normalizedName)
  }

  static async deletePlatformInstance(instanceId: string): Promise<void> {
    if (instanceId === '') {
      throw new ApiException(400, '邮箱服务标识无效', false)
    }
    await InstanceService.withPlatformSession((token: string): Promise<void> => {
      return PlatformApi.deleteInstance(token, instanceId)
    })
    SessionService.removeInstanceSession(instanceId)
  }

  static async importAnchorHuaweiAccounts(): Promise<PlatformImportResult> {
    const anchorToken: string = SessionService.getInstanceToken(InstanceRegistry.getDefaultInstanceId())
    if (anchorToken === '') {
      throw new ApiException(401, '主服务登录已失效，请重新登录华为账号', false)
    }
    return InstanceService.withPlatformSession((token: string): Promise<PlatformImportResult> => {
      return PlatformApi.importAnchorHuaweiAccounts(token, anchorToken)
    })
  }

  static async bindInstance(instance: PlatformInstance, email: string, password: string): Promise<InstanceBindResult> {
    if (email.trim() === '' || password === '') {
      return new InstanceBindResult(false, '请输入该实例的完整邮箱和密码')
    }
    try {
      const loginRequest: InstanceLoginRequest = new InstanceLoginRequest(email.trim(), password)
      const loginResponse: ApiResponse = await ExternalHttpClient.post(
        instance.apiBaseUrl, '/login', JSON.stringify(loginRequest))
      if (loginResponse.data === null) {
        return new InstanceBindResult(false, '实例未返回登录令牌')
      }
      const loginPayload: InstanceLoginPayload = loginResponse.data as InstanceLoginPayload
      if (loginPayload.token === '') {
        return new InstanceBindResult(false, '实例未返回登录令牌')
      }
      const user: AuthUserInfo = await InstanceService.loadInstanceUser(instance.apiBaseUrl, loginPayload.token)
      const binding: PlatformBindingPayload = await InstanceService.withPlatformSession(
        (token: string): Promise<PlatformBindingPayload> => {
          return PlatformApi.verifyBinding(token, instance.instanceId, loginPayload.token)
        })
      const localInstance: MailInstance = new MailInstance(
        instance.instanceId,
        instance.displayName,
        instance.apiBaseUrl,
        instance.originHost,
        user.email,
        user.role,
        user.roleName,
        user.accountId,
        binding.instanceRole
      )
      SessionService.saveInstanceSession(localInstance, loginPayload.token)
      return new InstanceBindResult(true, '', localInstance)
    } catch (err) {
      if (err instanceof ApiException) {
        return new InstanceBindResult(false, err.message)
      }
      return new InstanceBindResult(false, '实例绑定失败，请稍后重试')
    }
  }

  static getLocalInstances(): MailInstance[] {
    return InstanceRegistry.getInstances()
  }

  static switchInstance(instanceId: string): boolean {
    return SessionService.switchInstance(instanceId)
  }

  static removeInstance(instanceId: string): boolean {
    return SessionService.removeInstanceSession(instanceId)
  }

  static getAnchorEmail(): string {
    const instance: MailInstance | null = InstanceRegistry.find(InstanceRegistry.getDefaultInstanceId())
    return instance === null ? '' : instance.localEmail
  }

  static getAnchorApiBaseUrl(): string {
    const instance: MailInstance | null = InstanceRegistry.find(InstanceRegistry.getDefaultInstanceId())
    return instance === null ? '' : instance.apiBaseUrl
  }

  static getAnchorToken(): string {
    return SessionService.getInstanceToken(InstanceRegistry.getDefaultInstanceId())
  }

  private static async loadInstanceUser(apiBaseUrl: string, token: string): Promise<AuthUserInfo> {
    const response: ApiResponse = await ExternalHttpClient.get(apiBaseUrl, '/my/loginUserInfo', token)
    if (response.data === null) {
      throw new ApiException(-1, '实例未返回用户信息', false)
    }
    const payload: InstanceRemoteUser = response.data as InstanceRemoteUser
    const email: string = payload.email === undefined ? '' : payload.email
    if (email === '') {
      throw new ApiException(-1, '实例未返回用户邮箱', false)
    }
    const roleName: string = payload.role === undefined || payload.role.name === undefined || payload.role.name === '' ?
      '普通用户' : payload.role.name
    const permKeys: string[] = payload.permKeys === undefined ? [] : payload.permKeys
    const accountId: number = payload.account === undefined || payload.account.accountId === undefined ?
      0 : payload.account.accountId
    const isAdmin: boolean = InstanceService.isAdministrator(roleName, permKeys)
    return new AuthUserInfo(email, isAdmin ? 'admin' : 'user', roleName, accountId)
  }

  private static isAdministrator(roleName: string, permKeys: string[]): boolean {
    if (roleName === 'admin') {
      return true
    }
    for (let index = 0; index < permKeys.length; index++) {
      if (permKeys[index] === '*') {
        return true
      }
    }
    return false
  }

  private static async withPlatformSession<T>(operation: (token: string) => Promise<T>): Promise<T> {
    const ready: boolean = await InstanceService.ensurePlatformSession()
    if (!ready) {
      throw new ApiException(401, '平台身份尚未建立，请先重新登录华为账号', false)
    }
    try {
      return await operation(PlatformSessionService.getToken())
    } catch (err) {
      if (!(err instanceof ApiException)) {
        throw new ApiException(-1, '平台服务请求失败，请稍后重试', true)
      }
      if (err.code !== 401) {
        throw err
      }
    }
    const renewed: boolean = await InstanceService.ensurePlatformSession(true)
    if (!renewed) {
      throw new ApiException(401, '平台登录已过期，请重新登录华为账号', false)
    }
    return operation(PlatformSessionService.getToken())
  }
}
