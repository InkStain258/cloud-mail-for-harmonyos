import { pasteboard } from '@kit.BasicServicesKit'
import Constants from '../common/Constants'

@Component
export struct VerificationCodeCard {
  @Prop code: string = ''
  @Prop compact: boolean = false
  @State copying: boolean = false
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.copying = false
  }

  aboutToDisappear(): void {
    this.active = false
  }

  private async showToast(resource: Resource): Promise<void> {
    if (!this.active) { return }
    try {
      await this.getUIContext().getPromptAction().openToast({ message: resource })
    } catch (err) {
      // The containing page may disappear before the clipboard/toast operation finishes.
    }
  }

  private async copyCode(): Promise<void> {
    if (!this.active || this.copying || this.code === '') { return }
    this.copying = true
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code)
      const property: pasteboard.PasteDataProperty = data.getProperty()
      // Verification codes must not silently sync to other devices via the clipboard.
      property.shareOption = pasteboard.ShareOption.LOCALDEVICE
      data.setProperty(property)
      await pasteboard.getSystemPasteboard().setData(data)
      await this.showToast($r('app.string.verification_code_copied'))
    } catch (err) {
      await this.showToast($r('app.string.verification_code_copy_failed'))
    } finally {
      if (this.active) { this.copying = false }
    }
  }

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text($r('app.string.verification_code_title'))
          .fontSize(this.compact ? 11 : 12)
          .fontColor($r('app.color.text_secondary'))
        Text(this.code)
          .fontSize(this.compact ? 16 : 22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button($r('app.string.verification_code_copy'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .height(40)
        .enabled(!this.copying)
        .onClick(() => { this.copyCode() })
    }
    .width('100%')
    .padding(this.compact ? 8 : 12)
    .borderRadius(Constants.RADIUS_SMALL)
    .backgroundColor($r('app.color.background'))
  }
}
