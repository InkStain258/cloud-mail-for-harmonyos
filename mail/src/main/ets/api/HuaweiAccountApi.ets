import { ApiException, ApiResponse, HttpClient, QueryParameter } from '../common/HttpClient'

class RemoteHuaweiBinding {
  huaweiAccountId: number = 0
  huaweiUserId: string = ''
  nickName: string = ''
  avatarUrl: string = ''
  primaryEmail: string = ''
  profileUpdateTime: string = ''
  createTime: string = ''
}

class RemoteHuaweiBindingPage {
  list: RemoteHuaweiBinding[] = []
  total: number = 0
  page: number = 1
  size: number = 20
}

export class HuaweiAccountBinding {
  id: number
  huaweiUserId: string
  nickName: string
  avatarUrl: string
  primaryEmail: string
  profileUpdateTime: string
  createTime: string

  constructor(source: RemoteHuaweiBinding) {
    this.id = source.huaweiAccountId
    this.huaweiUserId = source.huaweiUserId
    this.nickName = source.nickName
    this.avatarUrl = source.avatarUrl
    this.primaryEmail = source.primaryEmail
    this.profileUpdateTime = source.profileUpdateTime
    this.createTime = source.createTime
  }
}

export class HuaweiAccountBindingPage {
  list: HuaweiAccountBinding[]
  total: number
  page: number
  size: number

  constructor(list: HuaweiAccountBinding[], total: number, page: number, size: number) {
    this.list = list
    this.total = total
    this.page = page
    this.size = size
  }
}

export class HuaweiAccountApi {
  static async current(): Promise<HuaweiAccountBinding | null> {
    const response: ApiResponse = await HttpClient.get('/huawei/me')
    if (response.data === null) {
      return null
    }
    return new HuaweiAccountBinding(response.data as RemoteHuaweiBinding)
  }

  static async bindings(keyword: string, page: number, size: number): Promise<HuaweiAccountBindingPage> {
    const path: string = HttpClient.appendQuery('/huawei/admin/list', [
      new QueryParameter('keyword', keyword),
      new QueryParameter('page', page.toString()),
      new QueryParameter('size', size.toString())
    ])
    const response: ApiResponse = await HttpClient.get(path)
    if (response.data === null) {
      throw new ApiException(-1, '服务器未返回华为账号绑定信息', false)
    }
    const remotePage: RemoteHuaweiBindingPage = response.data as RemoteHuaweiBindingPage
    const list: HuaweiAccountBinding[] = []
    for (let i = 0; i < remotePage.list.length; i++) {
      list.push(new HuaweiAccountBinding(remotePage.list[i]))
    }
    return new HuaweiAccountBindingPage(list, remotePage.total, remotePage.page, remotePage.size)
  }
}
