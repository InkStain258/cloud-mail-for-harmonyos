import { ApiException, ApiResponse } from './HttpClient'
import { EmailApi } from '../api/EmailApi'
import { MailAttachment, MailItem } from './MailModels'
import { DateTimeUtils } from './DateTimeUtils'
import { MailStatsStore } from './MailStatsStore'
import { SessionService } from './SessionService'
import { NativeCapabilities } from './NativeCapabilities'
import { MailDetailCache } from './MailDetailCache'

class RemoteAttachment {
  filename: string | null = null
  key: string = ''
}

class RemoteEmail {
  emailId: number = 0
  sendEmail: string | null = null
  name: string | null = null
  accountId: number = 0
  subject: string | null = null
  text: string | null = null
  content: string | null = null
  listText: string | null = null
  code: string | null = null
  cc: string | null = null
  bcc: string | null = null
  toEmail: string = ''
  toName: string = ''
  type: number = 0
  unread: number = 0
  createTime: string = ''
  isStar: number = 0
  attList: RemoteAttachment[] = []
}

class RemoteMailList {
  list: RemoteEmail[] = []
  total: number = -1
}

class MailOrigin {
  instanceId: string = SessionService.getActiveInstanceId()
  apiBaseUrl: string = SessionService.getApiBaseUrl()
  ownerEmail: string = (AppStorage.get('authEmail') as string) || ''
  scope: string = NativeCapabilities.sessionKey()
}

export class MailPage {
  items: MailItem[]
  total: number
  nextCursor: number
  hasMore: boolean

  constructor(items: MailItem[], total: number, hasMore: boolean = false) {
    this.items = items
    this.total = total
    this.nextCursor = items.length > 0 ? items[items.length - 1].id : 0
    this.hasMore = hasMore
  }
}

class SendMailRequest {
  accountId: number
  name: string
  sendType: string
  emailId: number
  receiveEmail: string[]
  text: string
  content: string
  subject: string
  attachments: MailAttachment[]

  constructor(accountId: number, receiveEmail: string[], subject: string, content: string, sendType: string, emailId: number,
    attachments: MailAttachment[]) {
    this.accountId = accountId
    this.name = ''
    this.sendType = sendType
    this.emailId = emailId
    this.receiveEmail = receiveEmail
    this.text = content
    this.content = content
    this.subject = subject
    this.attachments = attachments
  }
}

export class MailService {
  static initialize(): void {
    AppStorage.setOrCreate('mailRevision', 0)
    MailStatsStore.initialize()
  }

  static async loadInbox(): Promise<MailItem[]> {
    const page: MailPage = await MailService.loadInboxPage(0)
    return page.items
  }

  static async loadInboxPage(emailId: number, requireFull: boolean = false): Promise<MailPage> {
    const origin: MailOrigin = new MailOrigin()
    const full: boolean = requireFull || !(await NativeCapabilities.current()).summaryDetail
    MailService.ensureOrigin(origin)
    // 收件箱按当前用户聚合主邮箱和全部副邮箱，服务端 allReceive=1 会忽略单个 accountId 过滤。
    const response: ApiResponse = await EmailApi.list(MailService.getCurrentAccountId(), 1, emailId, 0, 50, 0, full)
    const page: MailPage = MailService.toPage(response, emailId, origin, full)
    if (page.total >= 0) { MailStatsStore.syncReceive(page.total) }
    return page
  }

  static async loadSent(): Promise<MailItem[]> {
    return (await MailService.loadSentPage(0)).items
  }

  static async loadSentPage(emailId: number): Promise<MailPage> {
    const origin: MailOrigin = new MailOrigin()
    const full: boolean = !(await NativeCapabilities.current()).summaryDetail
    MailService.ensureOrigin(origin)
    const response: ApiResponse = await EmailApi.list(MailService.getCurrentAccountId(), 0, emailId, 0, 50, 1, full)
    const page: MailPage = MailService.toPage(response, emailId, origin, full)
    if (page.total >= 0) { MailStatsStore.syncSent(page.total) }
    return page
  }

  static async loadStarred(): Promise<MailItem[]> {
    return (await MailService.loadStarredPage(0)).items
  }

  static async loadStarredPage(emailId: number): Promise<MailPage> {
    const origin: MailOrigin = new MailOrigin()
    const full: boolean = !(await NativeCapabilities.current()).summaryDetail
    MailService.ensureOrigin(origin)
    const response: ApiResponse = await EmailApi.listStarred(emailId, 50, full)
    const page: MailPage = MailService.toPage(response, emailId, origin, full)
    if (page.total >= 0) { MailStatsStore.syncStar(page.total) }
    return page
  }

  static async markRead(emailId: number): Promise<void> {
    await EmailApi.markRead([emailId])
  }

  static async loadDetail(item: MailItem): Promise<MailItem> {
    const origin: MailOrigin = new MailOrigin()
    if (item.instanceId !== origin.instanceId || item.apiBaseUrl !== origin.apiBaseUrl ||
      item.ownerEmail !== origin.ownerEmail || !Number.isSafeInteger(item.id) || item.id <= 0) {
      throw new ApiException(-2, '邮件所属账号已切换，请重新打开邮件', false)
    }
    MailDetailCache.selectScope(origin.scope)
    if (item.detailLoaded) { return item.copy() }
    const cached: MailItem | null = MailDetailCache.get(item.id)
    if (cached !== null) {
      cached.unread = item.unread
      cached.starred = item.starred
      return cached
    }
    if (!(await NativeCapabilities.current()).summaryDetail) {
      throw new ApiException(-3, '当前服务不支持按需详情，请返回列表刷新后重试', false)
    }
    MailService.ensureOrigin(origin)
    const response: ApiResponse = await EmailApi.detail(item.id)
    MailService.ensureOrigin(origin)
    if (response.data === null || (response.data as RemoteEmail).emailId !== item.id) {
      throw new ApiException(-3, '邮件详情返回格式不正确，请重试', false)
    }
    const detail: MailItem = MailService.toItem(response.data as RemoteEmail)
    detail.instanceId = origin.instanceId
    detail.apiBaseUrl = origin.apiBaseUrl
    detail.ownerEmail = origin.ownerEmail
    detail.detailLoaded = true
    MailDetailCache.selectScope(origin.scope)
    MailDetailCache.put(detail)
    return detail
  }

  static async setStar(emailId: number, starred: boolean): Promise<void> {
    if (starred) {
      await EmailApi.addStar(emailId)
    } else {
      await EmailApi.cancelStar(emailId)
    }
    MailStatsStore.adjustStar(starred ? 1 : -1)
    MailDetailCache.selectScope(NativeCapabilities.sessionKey())
    MailDetailCache.remove(emailId)
    MailService.notifyChange()
  }

  static async delete(emailId: number): Promise<void> {
    await EmailApi.delete(emailId.toString())
    MailDetailCache.selectScope(NativeCapabilities.sessionKey())
    MailDetailCache.remove(emailId)
    MailService.notifyChange()
  }

  static async send(toEmail: string, ccEmail: string, bccEmail: string, subject: string, content: string,
    sendType: string, emailId: number, attachments: MailAttachment[], expectedInstanceId: string = '',
    expectedOwnerEmail: string = '', senderAccountId: number = 0): Promise<void> {
    if (expectedInstanceId !== '' && (expectedInstanceId !== SessionService.getActiveInstanceId() ||
      expectedOwnerEmail !== ((AppStorage.get('authEmail') as string) || ''))) {
      throw new ApiException(-2, '账号已切换，请返回原服务和账号后发送此草稿', false)
    }
    if (ccEmail.trim() !== '' || bccEmail.trim() !== '') {
      throw new ApiException(-1, '当前邮件服务暂不支持抄送和密送', false)
    }
    const recipients: string[] = MailService.splitRecipients(toEmail)
    if (recipients.length === 0) {
      throw new ApiException(-1, '请输入有效的收件人邮箱', false)
    }
    const request: SendMailRequest = new SendMailRequest(senderAccountId > 0 ? senderAccountId : MailService.getCurrentAccountId(), recipients, subject, content,
      sendType, emailId, attachments)
    await EmailApi.send(JSON.stringify(request))
    MailStatsStore.incrementSent()
    MailService.notifyChange()
  }

  private static getCurrentAccountId(): number {
    const accountId: number | undefined = AppStorage.get('currentAccountId') as number | undefined
    return accountId === undefined ? 0 : accountId
  }

  private static notifyChange(): void {
    const revision: number | undefined = AppStorage.get('mailRevision') as number | undefined
    AppStorage.set('mailRevision', revision === undefined ? 1 : revision + 1)
  }

  private static ensureOrigin(origin: MailOrigin): void {
    if (origin.scope !== NativeCapabilities.sessionKey()) {
      throw new ApiException(-2, '邮箱服务或登录账号已切换，已取消原请求', false)
    }
  }

  private static toPage(response: ApiResponse, cursor: number, origin: MailOrigin, full: boolean): MailPage {
    MailService.ensureOrigin(origin)
    const items: MailItem[] = MailService.toItems(response, origin, full)
    const remote: RemoteMailList | null = response.data as RemoteMailList | null
    let total: number = remote !== null && typeof remote.total === 'number' && Number.isFinite(remote.total)
      ? Math.max(0, remote.total) : -1
    const lastId: number = items.length > 0 ? items[items.length - 1].id : 0
    const hasMore: boolean = items.length >= 50 && lastId > 0 && (cursor === 0 || lastId < cursor) &&
      !(cursor === 0 && total >= 0 && total <= items.length)
    // A legacy /star/list response has no total. A later page's size is never the global total.
    if (cursor === 0 && !hasMore && total < 0) { total = items.length }
    return new MailPage(items, total, hasMore)
  }

  private static toItems(response: ApiResponse, origin: MailOrigin, full: boolean): MailItem[] {
    if (response.data === null) {
      return []
    }
    const remoteData: RemoteMailList = response.data as RemoteMailList
    if (!Array.isArray(remoteData.list)) {
      throw new ApiException(-3, '邮件列表返回格式不正确，请重试', false)
    }
    const result: MailItem[] = []
    for (let index = 0; index < remoteData.list.length; index++) {
      const item: MailItem = MailService.toItem(remoteData.list[index])
      item.instanceId = origin.instanceId
      item.apiBaseUrl = origin.apiBaseUrl
      item.ownerEmail = origin.ownerEmail
      item.detailLoaded = full
      result.push(item)
    }
    return result
  }

  private static toItem(remote: RemoteEmail): MailItem {
    const item: MailItem = new MailItem()
    const sendEmail: string = MailService.toSafeString(remote.sendEmail)
    const senderName: string = MailService.toSafeString(remote.name)
    const subject: string = MailService.toSafeString(remote.subject)
    const text: string = MailService.toSafeString(remote.text)
    const content: string = MailService.toSafeString(remote.content)
    item.id = remote.emailId
    item.accountId = typeof remote.accountId === 'number' ? remote.accountId : 0
    item.type = remote.type
    item.subject = subject
    item.body = text === '' ? (content === '' ? MailService.toSafeString(remote.listText) : content) : text
    const code: string = MailService.toSafeString(remote.code).trim()
    item.verificationCode = /^[A-Za-z0-9][A-Za-z0-9 -]{1,31}$/.test(code) ? code : ''
    item.htmlContent = content
    item.time = DateTimeUtils.formatUtcDateTime(remote.createTime)
    item.unread = remote.unread === 0
    item.starred = remote.isStar === 1
    item.cc = MailService.toAddressList(remote.cc)
    item.bcc = MailService.toAddressList(remote.bcc)
    item.toEmail = MailService.toSafeString(remote.toEmail)
    if (remote.type === 1) {
      item.name = MailService.toSafeString(remote.toName) || item.toEmail
      item.email = item.toEmail
    } else {
      item.name = senderName === '' ? sendEmail : senderName
      item.email = sendEmail
    }
    const attachments: RemoteAttachment[] = Array.isArray(remote.attList) ? remote.attList : []
    for (let index = 0; index < attachments.length; index++) {
      const filename: string = MailService.toSafeString(attachments[index].filename)
      if (filename !== '') {
        item.attList.push(filename)
        item.attachmentKeys.push(MailService.toSafeString(attachments[index].key))
      }
    }
    return item
  }

  private static toSafeString(value: string | null | undefined): string {
    return typeof value === 'string' ? value : ''
  }

  private static toAddressList(rawValue: string | null | undefined): string[] {
    if (typeof rawValue !== 'string' || rawValue === '') {
      return []
    }
    try {
      const values: string[] = JSON.parse(rawValue) as string[]
      const result: string[] = []
      for (let index = 0; index < values.length; index++) {
        if (values[index] !== '') {
          result.push(values[index])
        }
      }
      return result
    } catch (err) {
      return []
    }
  }

  private static splitRecipients(rawValue: string): string[] {
    const values: string[] = rawValue.replace('，', ',').replace(';', ',').split(',')
    const result: string[] = []
    for (let index = 0; index < values.length; index++) {
      const email: string = values[index].trim()
      if (email !== '' && email.indexOf('@') > 0 && email.indexOf('.') > 1) {
        result.push(email)
      }
    }
    return result
  }

}
