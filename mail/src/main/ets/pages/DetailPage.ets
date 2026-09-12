import Constants from "../common/Constants"
import { ApiException } from '../common/HttpClient'
import { MailDetailParams, MailItem } from '../common/MailModels'
import { MailService } from '../common/MailService'
import { SessionService } from '../common/SessionService'
import { MailResourceUrl } from '../common/MailResourceUrl'
import { NativeCapabilities } from '../common/NativeCapabilities'
import { VerificationCodeCard } from '../components/VerificationCodeCard'
import { SettingsApi, WebsiteConfig } from '../api/SettingsApi'
import { ComposeParams } from './ComposePage'
import { LengthMetrics, PromptAction } from "@kit.ArkUI"
import { http } from '@kit.NetworkKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { webview } from '@kit.ArkWeb'
import { ActionBarButton, ActionBarStyle, BlurStrategy, HdsActionBar, HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType, hdsMaterial, HdsNavDestinationTitleMode } from "@kit.UIDesignKit"

@Component
export struct DetailPageContent {
  private scroller: Scroller = new Scroller()
  @StorageLink('safeAreaBottomPx') safeAreaBottomPx: number = 0
  @Prop emailData: MailDetailParams = new MailDetailParams(new MailItem(), [], 0)
  private pathStack: NavPathStack | null = null
  @State email: MailItem = new MailItem()
  @State emailList: MailItem[] = []
  @State currentIndex: number = 0
  @State showDetail: boolean = false
  @State showCcBcc: boolean = false
  @State isStarred: boolean = false
  @State mediaBaseUrl: string = ''
  private toast: PromptAction = this.getUIContext().getPromptAction()
  private webController: webview.WebviewController = new webview.WebviewController()
  private isWebAttached: boolean = false
  private pageInstanceId: string = ''
  private pageOwnerEmail: string = ''
  private pageApiBaseUrl: string = ''
  private pageActive: boolean = false
  private downloading: boolean = false
  @State actionInFlight: boolean = false
  @State detailLoading: boolean = false
  @State detailError: string = ''
  private detailGeneration: number = 0
  private pageSessionScope: string = ''

  private replyAction: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.arrowshape_turn_up_left'),
    onClick: () => { this.replyEmail() },
    accessibilityText: '回复',
    hoverTips: '回复',
    id: 'detail-reply'
  })
  private forwardAction: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.arrowshape_turn_up_right'),
    onClick: () => { this.forwardEmail() },
    accessibilityText: '转发',
    hoverTips: '转发',
    id: 'detail-forward'
  })
  private starAction: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.star'),
    altIcon: $r('sys.symbol.star_fill'),
    onClick: () => { this.toggleStar() },
    accessibilityText: '星标',
    hoverTips: '星标',
    id: 'detail-star'
  })
  private deleteAction: ActionBarButton = new ActionBarButton({
    baseIcon: $r('sys.symbol.trash'),
    onClick: () => { this.deleteEmail() },
    accessibilityText: '删除',
    hoverTips: '删除',
    id: 'detail-delete'
  })
  private startActions: ActionBarButton[] = [this.replyAction, this.forwardAction]
  private endActions: ActionBarButton[] = [this.deleteAction]

  aboutToAppear(): void {
    this.pathStack = AppStorage.get("appPathStack") as NavPathStack
    this.pageActive = true
    if (this.emailData.emailData !== undefined) {
      this.email = this.emailData.emailData
      this.emailList = this.emailData.emailList.slice()
      this.currentIndex = this.emailData.currentIndex
      this.isStarred = this.email.starred
    }
    this.pageInstanceId = this.email.instanceId || SessionService.getActiveInstanceId()
    this.pageOwnerEmail = this.email.ownerEmail || ((AppStorage.get('authEmail') as string) || '')
    this.pageApiBaseUrl = this.email.apiBaseUrl || SessionService.getApiBaseUrl()
    this.pageSessionScope = NativeCapabilities.sessionKey()
    this.mediaBaseUrl = this.getAttachmentBaseUrl()
    this.refreshMediaBaseUrl()
    this.loadSelectedDetail()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.detailGeneration++
    this.isWebAttached = false
  }

  private isOriginalSession(): boolean {
    return this.pageActive && this.pageSessionScope === NativeCapabilities.sessionKey() &&
      this.pageInstanceId === SessionService.getActiveInstanceId() &&
      this.pageOwnerEmail === ((AppStorage.get('authEmail') as string) || '') &&
      this.pageApiBaseUrl === SessionService.getApiBaseUrl()
  }

  private requireOriginalSession(): boolean {
    if (this.isOriginalSession()) { return true }
    this.showToast(this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.mail_source_changed').id))
    return false
  }

  private async loadSelectedDetail(): Promise<void> {
    const generation: number = ++this.detailGeneration
    this.detailError = ''
    this.detailLoading = !this.email.detailLoaded
    this.loadMailContent()
    if (!this.detailLoading) { return }
    const target: MailItem = this.email.copy()
    try {
      const detail: MailItem = await MailService.loadDetail(target)
      if (generation !== this.detailGeneration || !this.isOriginalSession() || this.email.id !== target.id) { return }
      this.email = detail
      this.isStarred = detail.starred
      this.emailList = this.emailList.map((item: MailItem) => item.id === detail.id ? detail.copy() : item)
      this.loadMailContent()
    } catch (err) {
      if (generation === this.detailGeneration && this.isOriginalSession()) {
        this.detailError = err instanceof ApiException ? err.message :
          this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.mail_detail_retry').id)
      }
    } finally {
      if (generation === this.detailGeneration && this.isOriginalSession()) { this.detailLoading = false }
    }
  }

  private requireCompleteDetail(): boolean {
    if (!this.requireOriginalSession()) { return false }
    if (this.email.detailLoaded) { return true }
    this.showToast(this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.mail_detail_not_ready').id))
    return false
  }

  private async refreshMediaBaseUrl(): Promise<void> {
    if (!this.isOriginalSession()) { return }
    try {
      const config: WebsiteConfig = await SettingsApi.getWebsiteConfig()
      if (!this.isOriginalSession()) { return }
      this.mediaBaseUrl = this.normalizeMediaBaseUrl(config.r2Domain)
    } catch (err) {
      this.mediaBaseUrl = this.getAttachmentBaseUrl()
    }
    if (this.isOriginalSession()) { this.loadMailContent() }
  }

  private loadMailContent(): void {
    if (!this.isWebAttached) {
      return
    }
    try {
      this.webController.loadData(this.buildMailDocument(), 'text/html', 'UTF-8', ' ', ' ')
    } catch (err) {
      console.error('load mail html failed')
    }
  }

  private buildMailDocument(): string {
    if (!this.email.detailLoaded) { return '<html><body></body></html>' }
    const head: string = '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0" ' +
      'charset="utf-8"><style>html,body{height:auto!important;min-height:1px!important;margin:0;padding:0;' +
      'background:transparent;color:CanvasText;color-scheme:light dark;overflow-wrap:anywhere;}' +
      'img,video{display:block;max-width:100%!important;height:auto!important;}table{max-width:100%!important;}' +
      'pre{white-space:pre-wrap;overflow-wrap:anywhere;}</style></head><body>'
    const tail: string = '</body></html>'
    if (this.isHtmlMail()) {
      return head + this.normalizeMailContent(this.email.htmlContent) + tail
    }
    return head + '<pre>' + this.escapeHtml(this.email.body) + '</pre>' + tail
  }

  private normalizeMailContent(content: string): string {
    const imageBaseUrl: string = this.mediaBaseUrl === '' ? this.getAttachmentBaseUrl() : this.mediaBaseUrl
    return content.replaceAll('{{domain}}/', imageBaseUrl).replaceAll('{{domain}}', imageBaseUrl)
  }

  private normalizeMediaBaseUrl(domain: string): string {
    return MailResourceUrl.mediaBase(domain, this.pageApiBaseUrl)
  }

  private isHtmlMail(): boolean {
    const content: string = this.email.htmlContent.trim().toLowerCase()
    return content.indexOf('<html') >= 0 || content.indexOf('<body') >= 0 || content.indexOf('<div') >= 0 ||
      content.indexOf('<p') >= 0 || content.indexOf('<img') >= 0 || content.indexOf('<table') >= 0 ||
      content.indexOf('<br') >= 0 || content.indexOf('<style') >= 0 || content.indexOf('<!doctype') >= 0
  }

  private escapeHtml(value: string): string {
    return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
        Column() {
          Blank().height(6)

          Text(this.email.subject)
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r("app.color.text_primary"))
            .width("100%").padding({ top: 2, bottom: 8, left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })

          if (!this.showDetail) {
            Row() {
              Text(this.email.name).fontSize(14).fontColor($r('app.color.success')).maxLines(1)
              Blank()
              Text("详情").fontSize(14).fontColor($r("app.color.primary")).onClick(() => { this.showDetail = true })
            }
            .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 2, bottom: 8 })
          } else {
            Column() {
              Row() {
                Text("发件人：").fontSize(14).fontColor($r("app.color.text_secondary"))
                Text(this.email.name).fontSize(14).fontColor($r("app.color.text_primary"))
                Blank()
                Text("隐藏").fontSize(14).fontColor($r("app.color.primary")).onClick(() => { this.showDetail = false })
              }
              .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, bottom: 2 })

              Row() {
                Blank().width(56)
                Text(this.email.email).fontSize(13).fontColor($r("app.color.text_secondary"))
              }
              .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })

              Row() {
                Text("收件人：").fontSize(14).fontColor($r("app.color.text_secondary"))
                Text(this.email.toEmail === '' ? '当前账户' : this.email.toEmail).fontSize(14).fontColor($r("app.color.text_primary"))
              }
              .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE }).margin({ top: 6 })

              Row() {
                Blank().width(56)
                Text(this.email.toEmail === '' ? this.email.email : this.email.toEmail).fontSize(13).fontColor($r("app.color.text_secondary"))
              }
              .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE }).margin({ top: 2 })

              Row() {
                Text('    时间：' + this.email.time).fontSize(14).fontColor($r("app.color.text_secondary"))
              }
              .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE }).margin({ top: 6 })
            }
            .width("100%").padding({ top: 2, bottom: 8 })
          }

          Divider().strokeWidth(0.5).color($r("app.color.divider"))

          if (this.email.verificationCode !== '') {
            VerificationCodeCard({ code: this.email.verificationCode })
              .margin({ top: 12, bottom: 12 })
          }
          if (this.detailLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(24).height(24).color($r('app.color.primary'))
              Text($r('app.string.mail_detail_loading')).fontSize(14).fontColor($r('app.color.text_secondary'))
            }.width('100%').padding({ top: 20, bottom: 20 }).justifyContent(FlexAlign.Center)
          } else if (this.detailError !== '') {
            Column({ space: 12 }) {
              Text(this.detailError).fontSize(14).fontColor($r('app.color.text_secondary'))
              Button($r('app.string.mail_detail_retry')).onClick(() => { this.loadSelectedDetail() })
            }.width('100%').padding(20)
          }

          Web({ src: 'about:blank', controller: this.webController, renderMode: RenderMode.SYNC_RENDER })
            .width('100%')
            .layoutMode(WebLayoutMode.FIT_CONTENT)
            .overScrollMode(OverScrollMode.NEVER)
            .javaScriptAccess(false)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .backgroundColor(Color.Transparent)
            .onControllerAttached(() => {
              this.isWebAttached = true
              this.loadMailContent()
            })

          ForEach(this.email.attList, (att: string, index: number) => {
            Row() {
              SymbolGlyph($r("sys.symbol.doc")).fontSize(24).fontColor([$r("app.color.primary")])
              Column() {
                Text(att).fontSize(14).fontColor($r("app.color.text_primary"))
                Text("点击下载").fontSize(11).fontColor($r("app.color.primary")).margin({ top: 2 })
              }.margin({ left: 12 }).layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r("sys.symbol.arrow_down_to_line")).fontSize(20).fontColor([$r("app.color.primary")])
            }
            .width("100%").padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 14, bottom: 14 })
            .backgroundColor($r("app.color.card")).borderRadius(10).margin({ top: 4, bottom: 4 })
            .onClick(() => { this.downloadAttachment(index, att) })
          })

          Blank().height(88)
          Blank().layoutWeight(1)
        }
        .width("100%")
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
      }
    .width("100%").height("100%").scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).clip(false)

        Row() {
          HdsActionBar({
            startButtons: this.startActions,
            primaryButton: this.starAction,
            endButtons: this.endActions,
            actionBarStyle: new ActionBarStyle({
              height: LengthMetrics.vp(64),
              backgroundBlurStyle: BlurStyle.COMPONENT_THICK,
              isPrimaryIconChanged: this.isStarred,
              margin: LengthMetrics.vp(0)
            }),
            isExpand: true,
            blurStrategy: BlurStrategy.ADAPTIVE
          })
        }
        .width("100%")
        .justifyContent(FlexAlign.Center)
        .margin({
          left: Constants.PADDING_EDGE,
          right: Constants.PADDING_EDGE,
          bottom: 16 + this.getUIContext().px2vp(this.safeAreaBottomPx)
        })
      }
      .width("100%").height("100%")
    }
    .titleBar({
      content: {
        title: { mainTitle: "" },
        menu: {
          maxCount: 2,
          value: [
            { content: { label: "上一封", icon: $r("sys.symbol.chevron_up"), isEnabled: !this.actionInFlight && this.currentIndex > 0, action: () => { this.prevEmail() } } },
            { content: { label: "下一封", icon: $r("sys.symbol.chevron_down"), isEnabled: !this.actionInFlight && this.currentIndex < this.emailList.length - 1, action: () => { this.nextEmail() } } }
          ]
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: { maskExtraHeight: 0 },
          contentStyle: {
            titleStyle: { mainTitleColor: $r("app.color.text_primary"), subTitleColor: $r("app.color.text_secondary") },
            menuStyle: { iconColor: $r("app.color.text_primary") },
            backIconStyle: { iconColor: $r("app.color.text_primary") }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: { maskExtraHeight: 0 },
          contentStyle: {
            titleStyle: { mainTitleColor: $r("app.color.text_primary"), subTitleColor: $r("app.color.text_secondary") },
            menuStyle: { iconColor: $r("app.color.text_primary") },
            backIconStyle: { iconColor: $r("app.color.text_primary") }
          }
        }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .onBackPressed(() => { if (this.pathStack !== null) { this.pathStack.pop() } return true })
    .width("100%").height("100%").backgroundColor($r("app.color.background"))
  }

  private prevEmail(): void {
    if (this.actionInFlight || !this.requireOriginalSession()) { return }
    if (this.currentIndex > 0) {
      this.currentIndex--
      this.email = this.emailList[this.currentIndex]
      this.showDetail = false
      this.isStarred = this.email.starred
      this.loadSelectedDetail()
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
    }
  }

  private nextEmail(): void {
    if (this.actionInFlight || !this.requireOriginalSession()) { return }
    if (this.currentIndex < this.emailList.length - 1) {
      this.currentIndex++
      this.email = this.emailList[this.currentIndex]
      this.showDetail = false
      this.isStarred = this.email.starred
      this.loadSelectedDetail()
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
    }
  }

  private async deleteEmail(): Promise<void> {
    if (this.actionInFlight || !this.requireCompleteDetail()) { return }
    this.actionInFlight = true
    const targetId: number = this.email.id
    try {
      await MailService.delete(targetId)
      if (!this.isOriginalSession()) { return }
      const remaining: MailItem[] = []
      for (let index = 0; index < this.emailList.length; index++) {
        if (this.emailList[index].id !== targetId) {
          remaining.push(this.emailList[index])
        }
      }
      this.emailList = remaining
      if (this.emailList.length === 0) {
        if (this.pathStack !== null) { this.pathStack.pop() }
        return
      }
      if (this.currentIndex >= this.emailList.length) {
        this.currentIndex = this.emailList.length - 1
      }
      this.email = this.emailList[this.currentIndex]
      this.showDetail = false
      this.isStarred = this.email.starred
      this.loadSelectedDetail()
      this.showToast('邮件已删除')
    } catch (err) {
      this.showRequestError(err)
    } finally {
      this.actionInFlight = false
    }
  }

  private replyEmail(): void {
    if (this.pathStack === null || !this.requireCompleteDetail()) {
      return
    }
    const prefix: string = this.email.subject.indexOf('Re:') === 0 ? '' : 'Re: '
    const params: ComposeParams = new ComposeParams(this.email.email, '', '', prefix + this.email.subject, '', 'reply', this.email.id)
    this.setComposeOrigin(params)
    this.pathStack.pushPathByName('ComposePage', params)
  }

  private forwardEmail(): void {
    if (this.pathStack === null || !this.requireCompleteDetail()) {
      return
    }
    const prefix: string = this.email.subject.indexOf('Fwd:') === 0 ? '' : 'Fwd: '
    const params: ComposeParams = new ComposeParams('', '', '', prefix + this.email.subject, this.email.body, 'forward', this.email.id)
    this.setComposeOrigin(params)
    this.pathStack.pushPathByName('ComposePage', params)
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 2000 })
    } catch (err) {
      console.error('openToast failed')
    }
  }

  private async toggleStar(): Promise<void> {
    if (this.actionInFlight || !this.requireCompleteDetail()) { return }
    this.actionInFlight = true
    const target: MailItem = this.email.copy()
    const nextStarred: boolean = !this.isStarred
    try {
      await MailService.setStar(target.id, nextStarred)
      if (!this.isOriginalSession()) { return }
      const nextEmail: MailItem = target
      nextEmail.starred = nextStarred
      this.email = nextEmail
      const updatedList: MailItem[] = []
      for (let index = 0; index < this.emailList.length; index++) {
        if (this.emailList[index].id === nextEmail.id) {
          updatedList.push(nextEmail)
        } else {
          updatedList.push(this.emailList[index])
        }
      }
      this.emailList = updatedList
      this.isStarred = nextStarred
      this.showToast(nextStarred ? '已加入星标' : '已取消星标')
    } catch (err) {
      this.showRequestError(err)
    } finally {
      this.actionInFlight = false
    }
  }

  private showRequestError(err: Error): void {
    if (err instanceof ApiException) {
      this.showToast(err.message)
      return
    }
    this.showToast('请求失败，请稍后重试')
  }

  private async downloadAttachment(index: number, filename: string): Promise<void> {
    if (this.downloading || !this.requireOriginalSession()) { return }
    if (index >= this.email.attachmentKeys.length || this.email.attachmentKeys[index] === '') {
      this.showToast('附件地址无效')
      return
    }
    const request: http.HttpRequest = http.createHttp()
    this.downloading = true
    try {
      const response: http.HttpResponse = await request.request(this.getAttachmentUrl(this.email.attachmentKeys[index]), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 10000,
        readTimeout: 30000
      })
      if (!this.isOriginalSession()) { return }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        this.showToast('下载附件失败')
        return
      }
      const content: ArrayBuffer = response.result as ArrayBuffer
      const context: Context = this.getUIContext().getHostContext() as Context
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [filename]
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context)
      const destinations: string[] = await documentPicker.save(options)
      if (destinations.length === 0 || !this.isOriginalSession()) {
        return
      }
      const file: fileIo.File = fileIo.openSync(destinations[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, content)
      } finally {
        fileIo.closeSync(file)
      }
      this.showToast('附件已保存')
    } catch (err) {
      this.showToast('下载附件失败，请重试')
    } finally {
      this.downloading = false
      request.destroy()
    }
  }

  private getAttachmentUrl(key: string): string {
    return MailResourceUrl.attachmentUrl(this.pageApiBaseUrl, key)
  }

  private getAttachmentBaseUrl(): string {
    return MailResourceUrl.attachmentBase(this.pageApiBaseUrl)
  }

  private setComposeOrigin(params: ComposeParams): void {
    params.instanceId = this.pageInstanceId
    params.ownerEmail = this.pageOwnerEmail
    params.senderAccountId = this.email.accountId
  }
}
