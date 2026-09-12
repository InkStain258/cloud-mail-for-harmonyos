import Constants from "../common/Constants"
import { ApiException } from '../common/HttpClient'
import { DraftOwner, DraftService, MailDraft } from '../common/DraftService'
import { DraftAttachment, DraftAttachmentStore } from '../common/DraftAttachmentStore'
import { MailAttachment } from '../common/MailModels'
import { MailService } from '../common/MailService'
import { LengthMetrics, PromptAction } from '@kit.ArkUI'
import { picker } from '@kit.CoreFileKit'
import { HdsNavDestination, HdsNavDestinationAttribute, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from "@kit.UIDesignKit"

export class ComposeParams {
  toEmail: string
  ccEmail: string
  bccEmail: string
  subject: string
  content: string
  sendType: string
  emailId: number
  draftId: number
  instanceId: string = ''
  ownerEmail: string = ''
  senderAccountId: number = 0

  constructor(toEmail: string = '', ccEmail: string = '', bccEmail: string = '', subject: string = '', content: string = '',
    sendType: string = '', emailId: number = 0, draftId: number = 0) {
    this.toEmail = toEmail
    this.ccEmail = ccEmail
    this.bccEmail = bccEmail
    this.subject = subject
    this.content = content
    this.sendType = sendType
    this.emailId = emailId
    this.draftId = draftId
  }
}

@Component
export struct ComposePageContent {
  private scroller: Scroller = new Scroller()
  @StorageLink('safeAreaBottomPx') safeAreaBottomPx: number = 0
  @Prop composeParams: ComposeParams = new ComposeParams()
  @State toEmail: string = ""
  @State ccEmail: string = ""
  @State bccEmail: string = ""
  @State subject: string = ""
  @State content: string = ""
  @State attachments: DraftAttachment[] = []
  @State sending: boolean = false
  @State choosingAttachments: boolean = false
  @State saveStatus: ResourceStr = $r('app.string.draft_status_new')
  @State ownerChanged: boolean = false
  @State uncertainSend: boolean = false
  @StorageLink('sessionRevision') @Watch('onSessionChanged') sessionRevision: number = 0
  private owner: DraftOwner = new DraftOwner()
  private senderAccountId: number = 0
  private sendType: string = ''
  private emailId: number = 0
  private sendState: string = ''
  private lastSnapshot: string = ''
  private saveTimer: number = -1
  private initialized: boolean = false
  private completed: boolean = false
  private leaving: boolean = false
  private editorFlush: () => void = (): void => {
    if (!this.saveDraftIfNeeded()) {
      throw new Error('Draft save failed')
    }
  }
  private draftId: number = 0
  private toast: PromptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.owner = DraftService.captureOwner()
    this.senderAccountId = this.composeParams.senderAccountId > 0 ?
      this.composeParams.senderAccountId : this.owner.accountId
    this.sendType = this.composeParams.sendType
    this.emailId = this.composeParams.emailId
    this.toEmail = this.composeParams.toEmail
    this.ccEmail = this.composeParams.ccEmail
    this.bccEmail = this.composeParams.bccEmail
    this.subject = this.composeParams.subject
    this.content = this.composeParams.content
    this.draftId = this.composeParams.draftId
    if ((this.composeParams.instanceId !== '' && this.composeParams.instanceId !== this.owner.instanceId) ||
      (this.composeParams.ownerEmail !== '' && this.composeParams.ownerEmail.trim() !== this.owner.email)) {
      this.ownerChanged = true
      this.saveStatus = $r('app.string.draft_owner_changed')
      return
    }
    if (this.draftId !== 0) {
      try {
        const draft: MailDraft = DraftService.getOwnedDraft(this.draftId, this.owner)
        this.toEmail = draft.toEmail
        this.ccEmail = draft.ccEmail
        this.bccEmail = draft.bccEmail
        this.subject = draft.subject
        this.content = draft.content
        this.attachments = draft.attachments
        this.senderAccountId = draft.senderAccountId
        this.sendType = draft.sendType
        this.emailId = draft.emailId
        this.sendState = draft.sendState
        this.uncertainSend = draft.sendState === 'pending' || draft.sendState === 'unknown'
        this.completed = draft.sendState === 'sent'
        this.saveStatus = this.completed ? $r('app.string.draft_sent_cleanup_failed') :
          (this.uncertainSend ? $r('app.string.draft_send_unknown') : $r('app.string.draft_status_saved'))
      } catch (err) {
        this.ownerChanged = true
        this.saveStatus = $r('app.string.draft_owner_changed')
        return
      }
    }
    this.initialized = true
    this.lastSnapshot = this.draftId === 0 ? '' : this.snapshotKey()
    DraftService.registerEditor(this.editorFlush)
    if (this.draftId === 0) { this.scheduleSave() }
  }

  aboutToDisappear(): void {
    this.leaving = true
    this.clearSaveTimer()
    if (!this.saveDraftIfNeeded()) {
      this.showToastResource($r('app.string.draft_save_failed'))
    }
    DraftService.unregisterEditor(this.editorFlush)
  }

  private onSessionChanged(): void {
    if (this.initialized && !DraftService.isCurrentOwner(this.owner)) {
      this.saveDraftIfNeeded()
      this.ownerChanged = true
      this.saveStatus = $r('app.string.draft_owner_changed')
    }
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          Text(this.saveStatus)
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8, bottom: 4 })
          Text($r('app.string.draft_sender_identity', this.owner.email))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Row() {
            Text("收件人").fontSize(14).fontWeight(FontWeight.Medium).fontColor($r("app.color.text_secondary")).width(56)
            TextInput({ placeholder: "输入邮箱地址", text: this.toEmail })
              .placeholderColor($r("app.color.text_tertiary")).fontColor($r("app.color.text_primary"))
              .backgroundColor(Color.Transparent).layoutWeight(1).height(44)
              .enabled(!this.sending && !this.ownerChanged && !this.completed)
              .onChange((v: string) => { this.toEmail = v; this.scheduleSave() })
          }
          .width("100%").padding({ top: 12, bottom: 12 })

          Divider().strokeWidth(0.5).color($r("app.color.divider"))

          Text($r('app.string.draft_cc_unsupported'))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ top: 8, bottom: 8 })
          if (this.ccEmail !== '' || this.bccEmail !== '') {
            Column({ space: 6 }) {
              Text($r('app.string.draft_legacy_cc', this.ccEmail, this.bccEmail))
                .fontSize(Constants.FONT_SIZE_SMALL)
                .fontColor($r('app.color.text_secondary'))
              Button($r('app.string.draft_clear_unsupported'))
                .enabled(!this.sending && !this.ownerChanged && !this.completed)
                .onClick(() => { this.ccEmail = ''; this.bccEmail = ''; this.scheduleSave() })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          Row() {
            Text("主题").fontSize(14).fontWeight(FontWeight.Medium).fontColor($r("app.color.text_secondary")).width(56)
            TextInput({ placeholder: "邮件主题", text: this.subject })
              .placeholderColor($r("app.color.text_tertiary")).fontColor($r("app.color.text_primary"))
              .backgroundColor(Color.Transparent).layoutWeight(1).height(44)
              .enabled(!this.sending && !this.ownerChanged && !this.completed)
              .onChange((v: string) => { this.subject = v; this.scheduleSave() })
          }
          .width("100%").padding({ top: 12, bottom: 12 })

          Divider().strokeWidth(0.5).color($r("app.color.divider"))

          TextArea({ placeholder: "写点什么...", text: this.content })
            .placeholderColor($r("app.color.text_tertiary")).fontColor($r("app.color.text_primary"))
            .backgroundColor(Color.Transparent).padding(Constants.PADDING_EDGE).height(300)
            .enabled(!this.sending && !this.ownerChanged && !this.completed)
            .onChange((v: string) => { this.content = v; this.scheduleSave() })

          Row() {
            Button('添加附件', { type: ButtonType.Normal, stateEffect: true })
              .height(36)
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.primary'))
              .backgroundColor($r('app.color.primary_light'))
              .enabled(!this.sending && !this.choosingAttachments && !this.ownerChanged && !this.completed)
              .onClick(() => { this.chooseAttachments() })
            Text(this.attachments.length === 0 ? '最多 10 个附件' : '已添加 ' + this.attachments.length.toString() + ' 个附件')
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: Constants.GAP_SMALL })
          }
          .width('100%')
          .padding({ top: 8, bottom: 4 })

          ForEach(this.attachments, (item: DraftAttachment, index: number) => {
            Row() {
              SymbolGlyph($r('sys.symbol.doc'))
                .fontSize(Constants.SIZE_ICON_SMALL)
                .fontColor([$r('app.color.primary')])
              Text(item.filename)
                .fontSize(Constants.FONT_SIZE_SMALL)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: Constants.GAP_SMALL })
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(Constants.SIZE_ICON_SMALL)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(28)
              .height(28)
              .backgroundColor(Color.Transparent)
              .enabled(!this.sending && !this.choosingAttachments && !this.ownerChanged && !this.completed)
              .onClick(() => { this.removeAttachment(index) })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6, left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_SMALL)
            .margin({ top: 2, bottom: 2 })
          }, (item: DraftAttachment): string => item.storageName)

          Row() {
            SymbolGlyph($r("sys.symbol.paperplane_fill"))
              .fontSize(20).fontColor([$r("sys.color.icon_on_primary")])
            Text(this.sending ? $r('app.string.draft_sending') : $r('app.string.draft_send'))
              .fontSize(13).fontColor($r("sys.color.icon_on_primary")).margin({ left: 4 })
          }
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 10, bottom: 10 })
          .backgroundColor($r("app.color.primary")).borderRadius(22)
          .enabled(!this.sending && !this.choosingAttachments && !this.ownerChanged && !this.completed)
          .opacity(this.sending || this.choosingAttachments || this.ownerChanged || this.completed ? 0.5 : 1)
          .onClick(() => { this.requestSend() })
          .justifyContent(FlexAlign.Center).width("100%")
          .padding({ top: 12, bottom: 16 })

          Blank().height(20)
        }
        .width("100%")
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        .alignItems(HorizontalAlign.Start)
      }
      .width("100%").height("100%")
      .padding({ bottom: this.getUIContext().px2vp(this.safeAreaBottomPx) })
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).clip(false)
    }
    .titleBar({
      content: { title: { mainTitle: "写邮件" } },
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
            titleStyle: { mainTitleColor: $r("app.color.text_primary") },
            backIconStyle: { iconColor: $r("app.color.text_primary") }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: { maskExtraHeight: 0 },
          contentStyle: {
            titleStyle: { mainTitleColor: $r("app.color.text_primary") },
            backIconStyle: { iconColor: $r("app.color.text_primary") }
          }
        }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .onBackPressed(() => {
      if (this.sending || this.choosingAttachments) {
        this.showToastResource($r('app.string.draft_wait_operation'))
        return true
      }
      if (!this.saveDraftIfNeeded()) {
        this.showToastResource($r('app.string.draft_save_failed'))
        return true
      }
      const stack: NavPathStack | null = AppStorage.get("appPathStack") as NavPathStack
      if (stack !== null) { stack.pop() }
      return true
    })
    .width("100%").height("100%")
    .backgroundColor($r("app.color.background"))
  }

  private async requestSend(): Promise<void> {
    if (this.sending || this.choosingAttachments || this.completed || this.ownerChanged) {
      return
    }
    if (this.uncertainSend) {
      try {
        const result = await this.toast.showDialog({
          title: $r('app.string.draft_retry_title'),
          message: $r('app.string.draft_retry_message'),
          buttons: [
            { text: $r('app.string.draft_cancel'), color: $r('app.color.text_secondary') },
            { text: $r('app.string.draft_retry_confirm'), color: $r('app.color.danger') }
          ]
        })
        if (result.index !== 1) { return }
      } catch (err) { return }
    }
    await this.sendEmail()
  }

  private async sendEmail(): Promise<void> {
    if (this.sending || this.choosingAttachments || this.completed || !DraftService.isCurrentOwner(this.owner)) {
      this.showToastResource($r('app.string.draft_owner_changed'))
      return
    }
    if (this.toEmail.trim() === '') {
      this.showToast('请输入收件人邮箱')
      return
    }
    if (this.subject.trim() === '') {
      this.showToast('请输入邮件主题')
      return
    }
    if (this.content.trim() === '') {
      this.showToast('请输入邮件正文')
      return
    }
    if (this.ccEmail.trim() !== '' || this.bccEmail.trim() !== '') {
      this.showToastResource($r('app.string.draft_cc_blocked'))
      return
    }
    if (!this.saveDraftIfNeeded()) {
      this.showToastResource($r('app.string.draft_save_failed'))
      return
    }
    this.sending = true
    let dispatched: boolean = false
    try {
      const files: MailAttachment[] = await DraftAttachmentStore.readForSending(this.attachments)
      if (!DraftService.isCurrentOwner(this.owner)) {
        throw new ApiException(-2, this.resourceText($r('app.string.draft_owner_changed')), false)
      }
      // Persist an in-flight marker before dispatch. After interruption, require explicit retry confirmation.
      this.sendState = 'pending'
      if (!this.saveDraftIfNeeded()) {
        this.sendState = ''
        this.showToastResource($r('app.string.draft_save_failed'))
        return
      }
      dispatched = true
      await MailService.send(this.toEmail, this.ccEmail, this.bccEmail, this.subject, this.content,
        this.sendType, this.emailId, files, this.owner.instanceId, this.owner.email, this.senderAccountId)
      this.completed = true
      this.sendState = 'sent'
      this.showToast('邮件已发送')
      try {
        DraftService.deleteDraft(this.draftId, this.owner)
      } catch (err) {
        // Never turn a successful send into an invitation to resend when local cleanup fails.
        try { DraftService.saveDraft(this.snapshot()) } catch (storageError) {
          console.error('Sent draft cleanup could not be persisted')
        }
        this.saveStatus = $r('app.string.draft_sent_cleanup_failed')
        this.showToastResource($r('app.string.draft_sent_cleanup_failed'))
        return
      }
      this.draftId = 0
      const stack: NavPathStack | null = AppStorage.get("appPathStack") as NavPathStack
      if (stack !== null) { stack.pop() }
    } catch (err) {
      this.uncertainSend = dispatched && (!(err instanceof ApiException) || err.code < 0 || err.retryable)
      this.sendState = this.uncertainSend ? 'unknown' : ''
      const saved: boolean = this.saveDraftIfNeeded()
      if (!saved) {
        this.showToastResource($r('app.string.draft_save_failed'))
      } else if (this.uncertainSend) {
        this.saveStatus = $r('app.string.draft_send_unknown')
        this.showToastResource($r('app.string.draft_send_unknown'))
      } else if (err instanceof ApiException) {
        this.showToast(err.message)
      } else {
        this.showToastResource($r('app.string.draft_attachment_restore_failed'))
      }
    } finally {
      this.sending = false
    }
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1800 })
    } catch (err) {
      console.error('openToast failed')
    }
  }

  private resourceText(resource: Resource): string {
    const context: Context = this.getUIContext().getHostContext() as Context
    return context.resourceManager.getStringSync(resource.id)
  }

  private showToastResource(resource: Resource): void {
    this.showToast(this.resourceText(resource))
  }

  private clearSaveTimer(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
  }

  private scheduleSave(): void {
    if (!this.initialized || this.completed || this.ownerChanged) { return }
    this.clearSaveTimer()
    this.saveStatus = $r('app.string.draft_status_saving')
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1
      this.saveDraftIfNeeded()
    }, 700)
  }

  private snapshot(): MailDraft {
    const draft: MailDraft = new MailDraft()
    draft.id = this.draftId
    draft.instanceId = this.owner.instanceId
    draft.ownerEmail = this.owner.email
    draft.senderAccountId = this.senderAccountId
    draft.toEmail = this.toEmail
    draft.ccEmail = this.ccEmail
    draft.bccEmail = this.bccEmail
    draft.subject = this.subject
    draft.content = this.content
    draft.sendType = this.sendType
    draft.emailId = this.emailId
    draft.attachments = this.attachments.slice()
    draft.sendState = this.sendState
    return draft
  }

  private snapshotKey(): string {
    const draft: MailDraft = this.snapshot()
    draft.id = 0
    return JSON.stringify(draft)
  }

  private saveDraftIfNeeded(): boolean {
    this.clearSaveTimer()
    if (!this.initialized || this.completed) { return true }
    const key: string = this.snapshotKey()
    if (key === this.lastSnapshot) {
      if (!this.ownerChanged) {
        this.saveStatus = this.uncertainSend ? $r('app.string.draft_send_unknown') : $r('app.string.draft_status_saved')
      }
      return true
    }
    const hasContent: boolean = this.toEmail.trim() !== '' || this.ccEmail.trim() !== '' || this.bccEmail.trim() !== '' ||
      this.subject.trim() !== '' || this.content.trim() !== '' || this.attachments.length > 0
    if (!hasContent && this.draftId === 0) {
      this.saveStatus = $r('app.string.draft_status_new')
      return true
    }
    try {
      if (!hasContent) {
        DraftService.deleteDraft(this.draftId, this.owner)
        this.draftId = 0
      } else {
        this.draftId = DraftService.saveDraft(this.snapshot())
      }
      this.lastSnapshot = this.snapshotKey()
      this.saveStatus = this.uncertainSend ? $r('app.string.draft_send_unknown') : $r('app.string.draft_status_saved')
      return true
    } catch (err) {
      this.saveStatus = $r('app.string.draft_save_failed')
      return false
    }
  }

  private async chooseAttachments(): Promise<void> {
    if (this.choosingAttachments || this.sending || this.completed || this.ownerChanged) { return }
    if (this.attachments.length >= 10) {
      this.showToast('最多添加 10 个附件')
      return
    }
    this.choosingAttachments = true
    try {
      const context: Context = this.getUIContext().getHostContext() as Context
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 10 - this.attachments.length
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentPicker.select(options)
      for (let index = 0; index < uris.length; index++) {
        if (this.leaving || !DraftService.isCurrentOwner(this.owner)) { break }
        const item: DraftAttachment = await DraftAttachmentStore.importUri(uris[index])
        if (this.leaving || !DraftService.isCurrentOwner(this.owner)) {
          DraftAttachmentStore.removeUnused([item], [])
          break
        }
        this.attachments = this.attachments.concat([item])
        if (!this.saveDraftIfNeeded()) {
          this.showToastResource($r('app.string.draft_save_failed'))
          break
        }
      }
    } catch (err) {
      this.showToastResource(err instanceof Error && err.message === 'ATTACHMENT_TOO_LARGE' ?
        $r('app.string.draft_attachment_too_large') : $r('app.string.draft_attachment_import_failed'))
    } finally {
      this.choosingAttachments = false
    }
  }

  private removeAttachment(index: number): void {
    const next: DraftAttachment[] = []
    for (let itemIndex = 0; itemIndex < this.attachments.length; itemIndex++) {
      if (itemIndex !== index) {
        next.push(this.attachments[itemIndex])
      }
    }
    this.attachments = next
    this.scheduleSave()
  }
}
