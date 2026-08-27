import Constants from '../common/Constants'
import { ExternalHttpClient } from '../common/ExternalHttpClient'
import { ApiException, ApiResponse } from '../common/HttpClient'
import {
  PlatformAdminBindingPage,
  PlatformAdminBindingPagePayload,
  PlatformBinding,
  PlatformBindingListPayload,
  PlatformBindingPayload,
  PlatformInstance,
  PlatformInstancePayload,
  PlatformImportResult,
  PlatformImportResultPayload,
  PlatformLoginPayload
} from '../common/InstanceModels'

class AnchorLoginRequest {
  instanceToken: string

  constructor(instanceToken: string) {
    this.instanceToken = instanceToken
  }
}

class CreateInstanceRequest {
  apiBaseUrl: string
  displayName: string

  constructor(apiBaseUrl: string, displayName: string) {
    this.apiBaseUrl = apiBaseUrl
    this.displayName = displayName
  }
}

class RenameInstanceRequest {
  displayName: string

  constructor(displayName: string) {
    this.displayName = displayName
  }
}

class VerifyBindingRequest {
  instanceToken: string

  constructor(instanceToken: string) {
    this.instanceToken = instanceToken
  }
}

class ImportAnchorHuaweiRequest {
  instanceToken: string

  constructor(instanceToken: string) {
    this.instanceToken = instanceToken
  }
}

class CreatedInstancePayload {
  instanceId: string = ''
  displayName: string = ''
  apiBaseUrl: string = ''
  originHost: string = ''
}

export class PlatformApi {
  static async loginThroughAnchor(instanceToken: string): Promise<PlatformLoginPayload> {
    const body: AnchorLoginRequest = new AnchorLoginRequest(instanceToken)
    const response: ApiResponse = await ExternalHttpClient.post(
      Constants.CONTROL_API_URL, '/api/platform/auth/anchor', JSON.stringify(body))
    if (response.data === null) {
      throw new ApiException(-1, '平台服务未返回登录信息', false)
    }
    const source: PlatformLoginPayload = response.data as PlatformLoginPayload
    const result: PlatformLoginPayload = new PlatformLoginPayload()
    result.token = source.token === undefined ? '' : source.token
    if (source.user !== undefined) {
      result.user.huaweiUserId = source.user.huaweiUserId === undefined ? '' : source.user.huaweiUserId
      result.user.nickName = source.user.nickName === undefined ? '' : source.user.nickName
      result.user.avatarUrl = source.user.avatarUrl === undefined ? '' : source.user.avatarUrl
      result.user.platformRole = source.user.platformRole === undefined ? 'MEMBER' : source.user.platformRole
    }
    if (result.token === '') {
      throw new ApiException(-1, '平台服务未返回登录令牌', false)
    }
    return result
  }

  static async instances(platformToken: string): Promise<PlatformInstance[]> {
    const response: ApiResponse = await ExternalHttpClient.get(
      Constants.CONTROL_API_URL, '/api/platform/instances', platformToken)
    if (response.data === null) {
      return []
    }
    const payloads: PlatformInstancePayload[] = response.data as PlatformInstancePayload[]
    const result: PlatformInstance[] = []
    for (let index = 0; index < payloads.length; index++) {
      result.push(new PlatformInstance(payloads[index]))
    }
    return result
  }

  static async createInstance(platformToken: string, apiBaseUrl: string, displayName: string):
    Promise<CreatedInstancePayload> {
    const request: CreateInstanceRequest = new CreateInstanceRequest(apiBaseUrl, displayName)
    const response: ApiResponse = await ExternalHttpClient.post(
      Constants.CONTROL_API_URL, '/api/platform/admin/instances', JSON.stringify(request), platformToken)
    if (response.data === null) {
      throw new ApiException(-1, '平台服务未返回实例信息', false)
    }
    return response.data as CreatedInstancePayload
  }

  static async renameInstance(platformToken: string, instanceId: string, displayName: string): Promise<void> {
    const request: RenameInstanceRequest = new RenameInstanceRequest(displayName)
    await ExternalHttpClient.put(
      Constants.CONTROL_API_URL,
      '/api/platform/admin/instances/' + encodeURIComponent(instanceId),
      JSON.stringify(request),
      platformToken
    )
  }

  static async deleteInstance(platformToken: string, instanceId: string): Promise<void> {
    await ExternalHttpClient.delete(
      Constants.CONTROL_API_URL,
      '/api/platform/admin/instances/' + encodeURIComponent(instanceId),
      platformToken
    )
  }

  static async verifyBinding(platformToken: string, instanceId: string, instanceToken: string):
    Promise<PlatformBindingPayload> {
    const request: VerifyBindingRequest = new VerifyBindingRequest(instanceToken)
    const response: ApiResponse = await ExternalHttpClient.post(
      Constants.CONTROL_API_URL,
      '/api/platform/instances/' + encodeURIComponent(instanceId) + '/verify-binding',
      JSON.stringify(request),
      platformToken
    )
    if (response.data === null) {
      throw new ApiException(-1, '平台服务未返回绑定结果', false)
    }
    return response.data as PlatformBindingPayload
  }

  static async myBindings(platformToken: string): Promise<PlatformBinding[]> {
    const response: ApiResponse = await ExternalHttpClient.get(
      Constants.CONTROL_API_URL, '/api/platform/me/bindings', platformToken)
    if (response.data === null) {
      return []
    }
    const payload: PlatformBindingListPayload = response.data as PlatformBindingListPayload
    const bindings: PlatformBinding[] = []
    const items: PlatformBindingPayload[] = payload.bindings === undefined ? [] : payload.bindings
    for (let index = 0; index < items.length; index++) {
      bindings.push(new PlatformBinding(items[index]))
    }
    return bindings
  }

  static async adminBindings(platformToken: string, keyword: string, page: number, size: number):
    Promise<PlatformAdminBindingPage> {
    const path: string = '/api/platform/admin/bindings?keyword=' + encodeURIComponent(keyword) +
      '&page=' + page.toString() + '&size=' + size.toString()
    const response: ApiResponse = await ExternalHttpClient.get(Constants.CONTROL_API_URL, path, platformToken)
    if (response.data === null) {
      throw new ApiException(-1, '平台服务未返回华为账号绑定信息', false)
    }
    return new PlatformAdminBindingPage(response.data as PlatformAdminBindingPagePayload)
  }

  static async importAnchorHuaweiAccounts(platformToken: string, instanceToken: string):
    Promise<PlatformImportResult> {
    const request: ImportAnchorHuaweiRequest = new ImportAnchorHuaweiRequest(instanceToken)
    const response: ApiResponse = await ExternalHttpClient.post(
      Constants.CONTROL_API_URL,
      '/api/platform/admin/import-anchor-huawei',
      JSON.stringify(request),
      platformToken
    )
    if (response.data === null) {
      throw new ApiException(-1, '平台服务未返回同步结果', false)
    }
    return new PlatformImportResult(response.data as PlatformImportResultPayload)
  }
}
