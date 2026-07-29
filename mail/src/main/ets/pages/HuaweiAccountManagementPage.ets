import { PromptAction } from '@kit.ArkUI'
import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'
import { HuaweiAccountApi, HuaweiAccountBinding, HuaweiAccountBindingPage } from '../api/HuaweiAccountApi'
import Constants from '../common/Constants'
import { DateTimeUtils } from '../common/DateTimeUtils'
import { EmptyState } from '../components/EmptyState'

@Component
export struct HuaweiAccountManagementPage {
  private scroller: Scroller = new Scroller()
  @StorageLink('authRole') authRole: string = 'user'
  @State keyword: string = ''
  @State bindings: HuaweiAccountBinding[] = []
  @State total: number = 0
  @State page: number = 1
  @State loading: boolean = false
  private readonly pageSize: number = 20
  private toast: PromptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.refresh()
  }

  build() {
    HdsNavDestination() {
      if (this.authRole !== 'admin') {
        EmptyState({ icon: $r('sys.symbol.person_2'), message: '仅管理员可查看华为账号绑定' })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column({ space: Constants.GAP_MEDIUM }) {
              Search({
                value: this.keyword,
                placeholder: '搜索华为账号或主邮箱'
              })
                .width('100%')
                .height(48)
                .searchButton('搜索', {
                  fontSize: Constants.FONT_SIZE_SMALL,
                  fontColor: $r('app.color.primary')
                })
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .textFont({ size: Constants.FONT_SIZE_COMMON })
                .backgroundColor($r('app.color.card'))
                .borderRadius(Constants.RADIUS_FULL)
                .onChange((value: string) => {
                  this.keyword = value
                  if (value === '' && !this.loading) {
                    this.refresh()
                  }
                })
                .onSubmit(() => {
                  this.refresh()
                })

              if (!this.loading || this.bindings.length > 0) {
                Text('共 ' + this.total.toString() + ' 个已绑定华为账号')
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }

              if (!this.loading && this.bindings.length === 0) {
                EmptyState({
                  icon: $r('sys.symbol.person_2'),
                  message: this.keyword.trim() === '' ? '暂无华为账号绑定记录' : '没有匹配的华为账号',
                  iconSize: 40
                })
                  .height(220)
              } else {
                Column({ space: Constants.GAP_SMALL }) {
                  ForEach(this.bindings, (item: HuaweiAccountBinding) => {
                    this.BindingCard(item)
                  }, (item: HuaweiAccountBinding): string => item.id.toString())
                }
                .width('100%')
              }

              if (this.bindings.length < this.total) {
                Button(this.loading ? '正在加载' : '加载更多', { type: ButtonType.Capsule, stateEffect: true })
                  .width('100%')
                  .height(44)
                  .enabled(!this.loading)
                  .fontColor($r('app.color.primary'))
                  .backgroundColor($r('app.color.card'))
                  .onClick(() => {
                    this.loadMore()
                  })
              }
              Blank().height(24)
            }
            .width('100%')
            .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 16, bottom: 24 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)

          if (this.loading && this.bindings.length === 0) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.primary'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .titleBar({
      content: { title: { mainTitle: '华为账号绑定' } },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private BindingCard(item: HuaweiAccountBinding) {
    Row({ space: Constants.GAP_MEDIUM }) {
      if (item.avatarUrl !== '') {
        Image(item.avatarUrl)
          .width(52)
          .height(52)
          .borderRadius(Constants.RADIUS_FULL)
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          Circle()
            .width(52)
            .height(52)
            .foregroundColor($r('app.color.primary_light'))
          Text(this.getAvatarText(item))
            .fontSize(Constants.FONT_SIZE_TITLE)
            .fontColor($r('app.color.primary'))
        }
        .width(52)
        .height(52)
      }

      Column({ space: 4 }) {
        Text(this.getHuaweiAccountLabel(item))
          .fontSize(Constants.FONT_SIZE_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('主邮箱：' + item.primaryEmail)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('绑定时间：' + DateTimeUtils.formatUtcDateTime(item.createTime, '未知'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(Constants.PADDING_CARD)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .shadow(Constants.SHADOW_CARD)
  }

  private async refresh(): Promise<void> {
    if (this.authRole !== 'admin' || this.loading) {
      return
    }
    this.loading = true
    try {
      const result: HuaweiAccountBindingPage =
        await HuaweiAccountApi.bindings(this.keyword.trim(), 1, this.pageSize)
      this.page = 1
      this.bindings = result.list
      this.total = result.total
    } catch (err) {
      this.showToast('加载华为账号绑定信息失败')
    }
    this.loading = false
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.bindings.length >= this.total) {
      return
    }
    this.loading = true
    try {
      const nextPage: number = this.page + 1
      const result: HuaweiAccountBindingPage =
        await HuaweiAccountApi.bindings(this.keyword.trim(), nextPage, this.pageSize)
      this.bindings = [...this.bindings, ...result.list]
      this.page = nextPage
      this.total = result.total
    } catch (err) {
      this.showToast('加载更多绑定信息失败')
    }
    this.loading = false
  }

  private getHuaweiAccountLabel(item: HuaweiAccountBinding): string {
    if (item.nickName !== '') {
      return item.nickName
    }
    return item.huaweiUserId === '' ? '华为账号资料待更新' : '华为账号 · ' + item.huaweiUserId
  }

  private getAvatarText(item: HuaweiAccountBinding): string {
    const value: string = item.nickName === '' ? item.primaryEmail : item.nickName
    return value === '' ? '华' : value.substring(0, 1).toUpperCase()
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1800 })
    } catch (err) {
      console.error('openToast failed')
    }
  }
}
