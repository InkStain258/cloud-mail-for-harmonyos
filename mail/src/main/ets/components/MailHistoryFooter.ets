import Constants from '../common/Constants'

@Component
export struct MailHistoryFooter {
  @Prop loading: boolean = false
  @Prop failed: boolean = false
  @Prop hasMore: boolean = false
  @Prop stalled: boolean = false
  onLoad: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      if (this.loading) {
        LoadingProgress().width(24).height(24).color($r('app.color.primary'))
        Text($r('app.string.mail_history_loading_more'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.stalled) {
        Text($r('app.string.mail_history_stalled'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      } else if (this.failed || this.hasMore) {
        if (this.failed) {
          Text($r('app.string.mail_history_load_failed'))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
        }
        Button(this.failed ? $r('app.string.mail_history_retry') : $r('app.string.mail_history_load_more'))
          .onClick(() => { this.onLoad() })
      } else {
        Text($r('app.string.mail_history_all_loaded'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: Constants.PADDING_TAB_CONTENT_BOTTOM })
  }
}
