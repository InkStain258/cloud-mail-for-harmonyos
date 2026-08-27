import { ExternalHttpClient } from '../common/ExternalHttpClient'
import { ApiException } from '../common/HttpClient'
import { InstanceService } from '../common/InstanceService'

class ResetPasswordRequest {
  password: string

  constructor(password: string) {
    this.password = password
  }
}

export class ProfileApi {
  static async resetPassword(password: string): Promise<void> {
    const anchorToken: string = ProfileApi.requireAnchorToken()
    await ExternalHttpClient.put(
      InstanceService.getAnchorApiBaseUrl(), '/my/resetPassword', JSON.stringify(new ResetPasswordRequest(password)),
      anchorToken)
  }

  static async deleteAccount(): Promise<void> {
    const anchorToken: string = ProfileApi.requireAnchorToken()
    await ExternalHttpClient.delete(InstanceService.getAnchorApiBaseUrl(), '/huawei/me', anchorToken)
  }

  private static requireAnchorToken(): string {
    const token: string = InstanceService.getAnchorToken()
    if (token === '' || InstanceService.getAnchorApiBaseUrl() === '') {
      throw new ApiException(401, '主服务登录已失效，请重新登录华为账号', false)
    }
    return token
  }
}
