export class MailInstancePayload {
  instanceId: string = ''
  displayName: string = ''
  apiBaseUrl: string = ''
  originHost: string = ''
  localEmail: string = ''
  localRole: string = 'user'
  localRoleName: string = '普通用户'
  accountId: number = 0
  instanceRole: string = 'MEMBER'
}

export class MailInstance {
  instanceId: string
  displayName: string
  apiBaseUrl: string
  originHost: string
  localEmail: string
  localRole: string
  localRoleName: string
  accountId: number
  instanceRole: string

  constructor(instanceId: string, displayName: string, apiBaseUrl: string, originHost: string,
    localEmail: string = '', localRole: string = 'user', localRoleName: string = '普通用户',
    accountId: number = 0, instanceRole: string = 'MEMBER') {
    this.instanceId = instanceId
    this.displayName = displayName
    this.apiBaseUrl = apiBaseUrl
    this.originHost = originHost
    this.localEmail = localEmail
    this.localRole = localRole
    this.localRoleName = localRoleName
    this.accountId = accountId
    this.instanceRole = instanceRole
  }

  static fromPayload(source: MailInstancePayload): MailInstance {
    return new MailInstance(
      source.instanceId === undefined ? '' : source.instanceId,
      source.displayName === undefined ? '' : source.displayName,
      source.apiBaseUrl === undefined ? '' : source.apiBaseUrl,
      source.originHost === undefined ? '' : source.originHost,
      source.localEmail === undefined ? '' : source.localEmail,
      source.localRole === undefined ? 'user' : source.localRole,
      source.localRoleName === undefined ? '普通用户' : source.localRoleName,
      source.accountId === undefined ? 0 : source.accountId,
      source.instanceRole === undefined ? 'MEMBER' : source.instanceRole
    )
  }
}

export class PlatformUser {
  huaweiUserId: string = ''
  nickName: string = ''
  avatarUrl: string = ''
  platformRole: string = 'MEMBER'
}

export class PlatformLoginPayload {
  token: string = ''
  user: PlatformUser = new PlatformUser()
}

export class PlatformImportResultPayload {
  imported: number = 0
  sourceTotal: number = 0
}

export class PlatformImportResult {
  imported: number
  sourceTotal: number

  constructor(source: PlatformImportResultPayload) {
    this.imported = source.imported === undefined ? 0 : source.imported
    this.sourceTotal = source.sourceTotal === undefined ? 0 : source.sourceTotal
  }
}

export class PlatformInstancePayload {
  instance_id: string = ''
  display_name: string = ''
  api_base_url: string = ''
  origin_host: string = ''
  status: string = ''
  local_email: string = ''
  local_role_name: string = ''
  instance_role: string = ''
  binding_status: string = ''
}

export class PlatformInstance {
  instanceId: string
  displayName: string
  apiBaseUrl: string
  originHost: string
  status: string
  localEmail: string
  localRoleName: string
  instanceRole: string
  bindingStatus: string

  constructor(source: PlatformInstancePayload) {
    this.instanceId = source.instance_id === undefined ? '' : source.instance_id
    this.displayName = source.display_name === undefined ? '' : source.display_name
    this.apiBaseUrl = source.api_base_url === undefined ? '' : source.api_base_url
    this.originHost = source.origin_host === undefined ? '' : source.origin_host
    this.status = source.status === undefined ? '' : source.status
    this.localEmail = source.local_email === undefined ? '' : source.local_email
    this.localRoleName = source.local_role_name === undefined ? '' : source.local_role_name
    this.instanceRole = source.instance_role === undefined ? '' : source.instance_role
    this.bindingStatus = source.binding_status === undefined ? '' : source.binding_status
  }
}

export class PlatformBindingPayload {
  bindingId: number = 0
  instanceId: string = ''
  displayName: string = ''
  apiBaseUrl: string = ''
  originHost: string = ''
  localEmail: string = ''
  localRoleName: string = ''
  instanceRole: string = ''
  verifiedTime: string = ''
}

export class PlatformBinding {
  bindingId: number
  instanceId: string
  displayName: string
  apiBaseUrl: string
  originHost: string
  localEmail: string
  localRoleName: string
  instanceRole: string
  verifiedTime: string

  constructor(source: PlatformBindingPayload) {
    this.bindingId = source.bindingId === undefined ? 0 : source.bindingId
    this.instanceId = source.instanceId === undefined ? '' : source.instanceId
    this.displayName = source.displayName === undefined ? '' : source.displayName
    this.apiBaseUrl = source.apiBaseUrl === undefined ? '' : source.apiBaseUrl
    this.originHost = source.originHost === undefined ? '' : source.originHost
    this.localEmail = source.localEmail === undefined ? '' : source.localEmail
    this.localRoleName = source.localRoleName === undefined ? '' : source.localRoleName
    this.instanceRole = source.instanceRole === undefined ? '' : source.instanceRole
    this.verifiedTime = source.verifiedTime === undefined ? '' : source.verifiedTime
  }
}

export class PlatformBindingListPayload {
  bindingCount: number = 0
  bindings: PlatformBindingPayload[] = []
}

export class PlatformAdminUserPayload {
  platformUserId: number = 0
  huaweiUserId: string = ''
  nickName: string = ''
  avatarUrl: string = ''
  platformRole: string = 'MEMBER'
  createTime: string = ''
  bindingCount: number = 0
  bindings: PlatformBindingPayload[] = []
}

export class PlatformAdminUser {
  platformUserId: number
  huaweiUserId: string
  nickName: string
  avatarUrl: string
  platformRole: string
  createTime: string
  bindingCount: number
  bindings: PlatformBinding[]

  constructor(source: PlatformAdminUserPayload) {
    this.platformUserId = source.platformUserId === undefined ? 0 : source.platformUserId
    this.huaweiUserId = source.huaweiUserId === undefined ? '' : source.huaweiUserId
    this.nickName = source.nickName === undefined ? '' : source.nickName
    this.avatarUrl = source.avatarUrl === undefined ? '' : source.avatarUrl
    this.platformRole = source.platformRole === undefined ? 'MEMBER' : source.platformRole
    this.createTime = source.createTime === undefined ? '' : source.createTime
    this.bindings = []
    const payloads: PlatformBindingPayload[] = source.bindings === undefined ? [] : source.bindings
    for (let index = 0; index < payloads.length; index++) {
      this.bindings.push(new PlatformBinding(payloads[index]))
    }
    this.bindingCount = this.bindings.length
  }
}

export class PlatformAdminBindingPagePayload {
  list: PlatformAdminUserPayload[] = []
  total: number = 0
  page: number = 1
  size: number = 20
}

export class PlatformAdminBindingPage {
  list: PlatformAdminUser[]
  total: number
  page: number
  size: number

  constructor(source: PlatformAdminBindingPagePayload) {
    this.list = []
    const payloads: PlatformAdminUserPayload[] = source.list === undefined ? [] : source.list
    for (let index = 0; index < payloads.length; index++) {
      this.list.push(new PlatformAdminUser(payloads[index]))
    }
    this.total = source.total === undefined ? 0 : source.total
    this.page = source.page === undefined ? 1 : source.page
    this.size = source.size === undefined ? 20 : source.size
  }
}
