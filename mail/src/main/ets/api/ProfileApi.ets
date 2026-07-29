import { HttpClient } from '../common/HttpClient'

class ResetPasswordRequest {
  password: string

  constructor(password: string) {
    this.password = password
  }
}

export class ProfileApi {
  static async resetPassword(password: string): Promise<void> {
    await HttpClient.put('/my/resetPassword', JSON.stringify(new ResetPasswordRequest(password)))
  }

  static async deleteAccount(): Promise<void> {
    await HttpClient.delete('/huawei/me')
  }
}
