import { ApiException, ApiResponse, HttpClient, QueryParameter } from '../common/HttpClient'

class RemoteHuaweiBinding {
  huaweiAccountId: number = 0
  huaweiUserId: string = ''
  nickName: string = ''
  avatarUrl: string = ''
  primaryEmail: string = ''
  profileUpdateTime: string = ''
  createTime: string = ''
  userCreateTime: string = ''
  receiveCount: number = 0
  sentCount: number = 0
  starCount: number = 0
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
  userCreateTime: string
  receiveCount: number
  sentCount: number
  starCount: number

  constructor(source: RemoteHuaweiBinding) {
    this.id = source.huaweiAccountId === undefined ? 0 : source.huaweiAccountId
    this.huaweiUserId = source.huaweiUserId === undefined ? '' : source.huaweiUserId
    this.nickName = source.nickName === undefined ? '' : source.nickName
    this.avatarUrl = source.avatarUrl === undefined ? '' : source.avatarUrl
    this.primaryEmail = source.primaryEmail === undefined ? '' : source.primaryEmail
    this.profileUpdateTime = source.profileUpdateTime === undefined ? '' : source.profileUpdateTime
    this.createTime = source.createTime === undefined ? '' : source.createTime
    this.userCreateTime = source.userCreateTime === undefined ? '' : source.userCreateTime
    this.receiveCount = source.receiveCount === undefined ? 0 : source.receiveCount
    this.sentCount = source.sentCount === undefined ? 0 : source.sentCount
    this.starCount = source.starCount === undefined ? 0 : source.starCount
  }

  static fromCache(huaweiUserId: string, nickName: string, avatarUrl: string, primaryEmail: string,
    profileUpdateTime: string, createTime: string, userCreateTime: string, receiveCount: number,
    sentCount: number, starCount: number): HuaweiAccountBinding {
    const remote: RemoteHuaweiBinding = new RemoteHuaweiBinding()
    remote.huaweiUserId = huaweiUserId
    remote.nickName = nickName
    remote.avatarUrl = avatarUrl
    remote.primaryEmail = primaryEmail
    remote.profileUpdateTime = profileUpdateTime
    remote.createTime = createTime
    remote.userCreateTime = userCreateTime
    remote.receiveCount = receiveCount
    remote.sentCount = sentCount
    remote.starCount = starCount
    return new HuaweiAccountBinding(remote)
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
