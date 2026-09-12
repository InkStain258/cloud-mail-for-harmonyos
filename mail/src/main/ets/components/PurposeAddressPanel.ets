import { common } from '@kit.AbilityKit'
import { LengthMetrics } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { HdsNavDestination, HdsNavDestinationTitleMode, IconStyleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'
import Constants from '../common/Constants'
import { NativeCapabilities, NativeCapabilityInfo } from '../common/NativeCapabilities'
import { PurposeAddressEntry, PurposeAddressRules } from '../common/PurposeAddressRules'
import { PurposeAddressScope, PurposeAddressStore } from '../common/PurposeAddressStore'

@Component
export struct PurposeAddressPanel {
  @Prop baseEmail: string = ''
  @State entries: PurposeAddressEntry[] = []
  @State label: string = ''
  @State tag: string = ''
  @State checking: boolean = true
  @State supported: boolean = false
  @State storageReady: boolean = false
  @State errorText: string = ''
  private scroller: Scroller = new Scroller()
  private scope: PurposeAddressScope = new PurposeAddressScope()
  private active: boolean = false
  onClose?: () => void

  aboutToAppear(): void {
    this.active = true
    this.scope = PurposeAddressStore.capture(this.baseEmail)
    this.loadLabels()
    this.checkCapability()
  }

  aboutToDisappear(): void {
    this.active = false
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: Constants.GAP_MEDIUM }) {
          Column({ space: 8 }) {
            Text(this.baseEmail)
              .fontSize(Constants.FONT_SIZE_SUBTITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .wordBreak(WordBreak.BREAK_ALL)
            Text($r('app.string.purpose_explanation'))
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(Constants.PADDING_EDGE)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.card'))
          .borderRadius(Constants.RADIUS_CARD)

          if (this.checking) {
            Text($r('app.string.purpose_checking'))
              .fontSize(Constants.FONT_SIZE_COMMON)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (!this.supported) {
            Column({ space: 8 }) {
              Text($r('app.string.purpose_unsupported'))
                .fontSize(Constants.FONT_SIZE_COMMON)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              Button($r('app.string.purpose_retry'), { type: ButtonType.Capsule })
                .fontColor($r('app.color.primary'))
                .backgroundColor($r('app.color.background'))
                .onClick(() => { this.checkCapability(true) })
            }
            .width('100%')
            .padding(Constants.PADDING_EDGE)
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
          }

          if (this.supported) {
            this.CreateCard()
          }

          if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(Constants.FONT_SIZE_COMMON)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }

          Text($r('app.string.purpose_saved_labels'))
            .fontSize(Constants.FONT_SIZE_COMMON)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          if (this.entries.length === 0 && this.storageReady) {
            Text($r('app.string.purpose_empty'))
              .fontSize(Constants.FONT_SIZE_COMMON)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding(Constants.PADDING_EDGE)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Constants.RADIUS_CARD)
          }

          ForEach(this.entries, (item: PurposeAddressEntry) => {
            this.AddressCard(item)
          }, (item: PurposeAddressEntry): string => item.tag)
        }
        .width('100%')
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }
    .titleBar({
      content: {
        title: { mainTitle: this.text($r('app.string.purpose_title')) },
        backIcon: {
          label: this.text($r('app.string.purpose_back')),
          icon: $r('sys.symbol.chevron_backward'), type: IconStyleMode.SMALL,
          action: () => { this.close() }
        },
        menu: {
          maxCount: 1,
          value: [{ content: {
            label: this.text($r('app.string.purpose_close')),
            icon: $r('sys.symbol.xmark'), type: IconStyleMode.SMALL,
            action: () => { this.close() }
          } }]
        }
      },
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
        originalStyle: { backgroundStyle: { maskExtraHeight: 0 } },
        scrollEffectStyle: { backgroundStyle: { maskExtraHeight: 0 } }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MODAL)
    .bindToScrollable([this.scroller])
    .onBackPressed(() => { this.close(); return true })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private CreateCard() {
    Column({ space: 10 }) {
      Text($r('app.string.purpose_create_title'))
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.label, placeholder: this.text($r('app.string.purpose_label_placeholder')) })
        .maxLength(30)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .height(48)
        .onChange((value: string) => { this.label = value })
      TextInput({ text: this.tag, placeholder: this.text($r('app.string.purpose_tag_placeholder')) })
        .maxLength(32)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .height(48)
        .onChange((value: string) => { this.tag = value })
      Text(this.preview())
        .fontSize(Constants.FONT_SIZE_SMALL)
        .fontColor($r('app.color.primary'))
        .width('100%')
        .wordBreak(WordBreak.BREAK_ALL)
      Button($r('app.string.purpose_save'), { type: ButtonType.Capsule })
        .width('100%')
        .height(44)
        .fontColor($r('sys.color.icon_on_primary'))
        .backgroundColor($r('app.color.primary'))
        .enabled(this.storageReady && this.tag.trim() !== '' && this.label.trim() !== '')
        .onClick(() => { this.save() })
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
  }

  @Builder
  private AddressCard(item: PurposeAddressEntry) {
    Column({ space: 8 }) {
      Text(item.label)
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(item.address)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .wordBreak(WordBreak.BREAK_ALL)
      Row({ space: 8 }) {
        Button($r('app.string.purpose_copy'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(40)
          .fontSize(Constants.FONT_SIZE_COMMON)
          .fontColor($r('app.color.primary'))
          .backgroundColor($r('app.color.background'))
          .enabled(this.supported)
          .onClick(() => { this.copy(item) })
        Button($r('app.string.purpose_remove'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(40)
          .fontSize(Constants.FONT_SIZE_COMMON)
          .fontColor($r('app.color.danger'))
          .backgroundColor($r('app.color.background'))
          .onClick(() => { this.confirmRemove(item) })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
  }

  private loadLabels(): void {
    try {
      this.entries = PurposeAddressStore.load(this.context(), this.scope)
      this.storageReady = true
    } catch (err) {
      this.storageReady = false
      this.showError(err as Error)
    }
  }

  private async checkCapability(forceRefresh: boolean = false): Promise<void> {
    if (!PurposeAddressStore.isCurrent(this.scope)) {
      this.close()
      return
    }
    this.checking = true
    this.supported = false
    try {
      const info: NativeCapabilityInfo = await NativeCapabilities.current(forceRefresh)
      if (this.active && PurposeAddressStore.isCurrent(this.scope)) {
        this.supported = info.purposeAddresses && PurposeAddressRules.isBaseMailbox(this.baseEmail)
      }
    } catch (err) {
      if (this.active) { this.supported = false }
    } finally {
      if (this.active) {
        this.checking = false
      }
    }
  }

  private save(): void {
    if (!this.supported || !this.storageReady) { return }
    try {
      this.entries = PurposeAddressStore.add(this.context(), this.scope, this.tag, this.label)
      this.label = ''
      this.tag = ''
      this.errorText = ''
      this.showToast($r('app.string.purpose_saved'))
    } catch (err) {
      this.showError(err as Error)
    }
  }

  private async copy(item: PurposeAddressEntry): Promise<void> {
    if (!this.supported || !PurposeAddressStore.isCurrent(this.scope)) { return }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, item.address)
      await pasteboard.getSystemPasteboard().setData(data)
      if (this.active && PurposeAddressStore.isCurrent(this.scope)) {
        this.showToast($r('app.string.purpose_copied'))
      }
    } catch (err) {
      this.showToast($r('app.string.purpose_copy_failed'))
    }
  }

  private confirmRemove(item: PurposeAddressEntry): void {
    this.getUIContext().showAlertDialog({
      title: this.text($r('app.string.purpose_remove')),
      message: this.text($r('app.string.purpose_remove_warning')),
      primaryButton: { value: this.text($r('app.string.purpose_cancel')), action: () => {} },
      secondaryButton: { value: this.text($r('app.string.purpose_remove')), action: () => {
        try {
          this.entries = PurposeAddressStore.remove(this.context(), this.scope, item.tag)
          this.errorText = ''
          this.showToast($r('app.string.purpose_removed'))
        } catch (err) {
          this.showError(err as Error)
        }
      } }
    })
  }

  private preview(): string {
    try {
      return PurposeAddressRules.create(this.baseEmail, this.tag, this.label.trim() || 'preview').address
    } catch (err) {
      return this.text($r('app.string.purpose_tag_hint'))
    }
  }

  private showError(error: Error): void {
    let message: Resource = $r('app.string.purpose_storage_failed')
    switch (error.message) {
      case 'purpose_invalid_tag': message = $r('app.string.purpose_invalid_tag'); break
      case 'purpose_invalid_label': message = $r('app.string.purpose_invalid_label'); break
      case 'purpose_invalid_mailbox': message = $r('app.string.purpose_invalid_mailbox'); break
      case 'purpose_address_too_long': message = $r('app.string.purpose_address_too_long'); break
      case 'purpose_duplicate': message = $r('app.string.purpose_duplicate'); break
      case 'purpose_limit': message = $r('app.string.purpose_limit'); break
      case 'purpose_session_changed': message = $r('app.string.purpose_session_changed'); break
    }
    this.errorText = this.text(message)
  }

  private close(): void { if (this.onClose) { this.onClose() } }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private text(resource: Resource): string {
    return this.context().resourceManager.getStringSync(resource.id)
  }

  private async showToast(resource: Resource): Promise<void> {
    if (!this.active || !PurposeAddressStore.isCurrent(this.scope)) { return }
    try {
      await this.getUIContext().getPromptAction().openToast({ message: this.text(resource), duration: 1500 })
    } catch (err) {
      // The sheet or its ability may disappear while a clipboard operation finishes.
    }
  }
}
