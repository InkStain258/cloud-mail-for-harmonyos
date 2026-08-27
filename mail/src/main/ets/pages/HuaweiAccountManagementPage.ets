import { PromptAction } from '@kit.ArkUI'
import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import Constants from '../common/Constants'
import { DateTimeUtils } from '../common/DateTimeUtils'
import { PlatformAdminBindingPage, PlatformAdminUser, PlatformBinding } from '../common/InstanceModels'
import { InstanceService } from '../common/InstanceService'
import { EmptyState } from '../components/EmptyState'

@Component
export struct HuaweiAccountManagementPage {
  private scroller: Scroller = new Scroller()
  @StorageLink('platformRole') platformRole: string = 'MEMBER'
  @State inputKeyword: string = ''
  @State appliedKeyword: string = ''
  @State accounts: PlatformAdminUser[] = []
  @State total: number = 0
  @State page: number = 1
  @State loading: boolean = false
  @State loadError: boolean = false
  @State syncError: boolean = false
  @State expandedAccountKeys: string[] = []
  private readonly pageSize: number = 20
  private requestSequence: number = 0
  private legacySyncAttempted: boolean = false
  private toast: PromptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.refresh(true)
  }

  build() {
    HdsNavDestination() {
      if (this.platformRole !== 'SUPER_ADMIN') {
        EmptyState({ icon: $r('sys.symbol.person_2'), message: '仅管理员可查看华为账号绑定' })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          List({ scroller: this.scroller, space: Constants.GAP_MEDIUM }) {
            ListItem() {
              Search({
                value: this.inputKeyword,
                placeholder: '搜索华为账号、邮箱或服务'
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
                  this.inputKeyword = value
                  if (value === '' && this.appliedKeyword !== '') {
                    this.appliedKeyword = ''
                    this.refresh()
                  }
                })
                .onSubmit(() => {
                  this.submitSearch()
                })
            }

            if (!this.loading && this.loadError) {
              ListItem() {
                Row({ space: Constants.GAP_SMALL }) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(Constants.SIZE_ICON_SMALL)
                    .fontColor([$r('app.color.danger')])
                  Text('加载失败，点击重试')
                    .fontSize(Constants.FONT_SIZE_SMALL)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .height(48)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.card'))
                .borderRadius(Constants.RADIUS_CARD)
                .onClick(() => { this.refresh() })
              }
            }

            if (!this.loading && this.syncError) {
              ListItem() {
                Row({ space: Constants.GAP_SMALL }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(Constants.SIZE_ICON_SMALL)
                    .fontColor([$r('app.color.primary')])
                  Text('旧账号同步未完成，点击重试')
                    .fontSize(Constants.FONT_SIZE_SMALL)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .height(48)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.card'))
                .borderRadius(Constants.RADIUS_CARD)
                .onClick(() => {
                  this.legacySyncAttempted = false
                  this.refresh(true)
                })
              }
            }

            if (!this.loading || this.accounts.length > 0) {
              ListItem() {
                Text('共 ' + this.total.toString() + ' 个华为账号')
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }

            if (!this.loading && !this.loadError && this.accounts.length === 0) {
              ListItem() {
                EmptyState({
                  icon: $r('sys.symbol.person_2'),
                  message: this.appliedKeyword === '' ? '暂无华为账号记录' :
                    '没有匹配的华为账号或邮箱',
                  iconSize: 40
                })
                  .height(220)
              }
            } else {
              ForEach(this.accounts, (item: PlatformAdminUser) => {
                ListItem() {
                  this.AccountBindingCard(item)
                }
              }, (item: PlatformAdminUser): string => item.platformUserId.toString())
            }

            if (this.accounts.length < this.total) {
              ListItem() {
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
            }

            ListItem() {
              Row().height(24)
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 4 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .clip(false)
          .cachedCount(3, true)

          if (this.loading && this.accounts.length === 0) {
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
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: { maskExtraHeight: 0 }
        },
        scrollEffectStyle: {
          backgroundStyle: { maskExtraHeight: 0 }
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
  private AccountBindingCard(item: PlatformAdminUser) {
    Column() {
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
          Text(this.getHuaweiAccountDescription(item))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('加入时间：' + DateTimeUtils.formatUtcDateTime(item.createTime, '未知'))
            .fontSize(Constants.FONT_SIZE_CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          Text(item.bindingCount.toString() + ' 个邮箱')
            .fontSize(Constants.FONT_SIZE_CAPTION)
            .fontColor($r('app.color.primary'))
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.background'))
            .borderRadius(Constants.RADIUS_FULL)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(Constants.SIZE_ICON_SMALL)
            .fontColor([$r('app.color.text_secondary')])
            .rotate({ angle: this.isAccountExpanded(item) ? 180 : 0 })
        }
      }
      .width('100%')
      .padding(Constants.PADDING_CARD)
      .onClick(() => {
        this.toggleExpanded(item)
      })

      if (this.isAccountExpanded(item)) {
        Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
        if (item.bindings.length === 0) {
          Text('该华为账号暂未绑定邮箱服务')
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Start)
        } else {
          ForEach(item.bindings, (binding: PlatformBinding, index: number) => {
            if (index > 0) {
              Divider().color($r('app.color.divider')).margin({ left: 64, right: 16 })
            }
            this.BindingRow(binding)
          }, (binding: PlatformBinding): string => binding.bindingId.toString() + '-' + binding.instanceId)
        }
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private BindingRow(item: PlatformBinding) {
    Row({ space: Constants.GAP_MEDIUM }) {
      Stack() {
        Circle()
          .width(36)
          .height(36)
          .foregroundColor($r('app.color.background'))
        SymbolGlyph($r('sys.symbol.envelope'))
          .fontSize(Constants.SIZE_ICON_SMALL)
          .fontColor([$r('app.color.primary')])
      }
      .width(36)
      .height(36)

      Column({ space: 3 }) {
        Text('主邮箱：' + item.localEmail)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_ALL)
        Text(item.displayName + ' · ' + item.originHost)
          .fontSize(Constants.FONT_SIZE_CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('绑定时间：' + DateTimeUtils.formatUtcDateTime(item.verifiedTime, '未知'))
          .fontSize(Constants.FONT_SIZE_CAPTION)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.getInstanceRoleLabel(item.instanceRole))
        .fontSize(Constants.FONT_SIZE_CAPTION)
        .fontColor($r('app.color.primary'))
        .maxLines(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  private async refresh(syncLegacy: boolean = false): Promise<void> {
    if (this.platformRole !== 'SUPER_ADMIN') {
      return
    }
    const requestId: number = ++this.requestSequence
    this.loading = true
    this.loadError = false
    try {
      if (syncLegacy && !this.legacySyncAttempted) {
        this.legacySyncAttempted = true
        try {
          await InstanceService.importAnchorHuaweiAccounts()
          if (requestId === this.requestSequence) {
            this.syncError = false
          }
        } catch (syncError) {
          if (requestId === this.requestSequence) {
            this.syncError = true
            this.showToast('旧账号同步失败，可点击重试')
          }
        }
      }
      const result: PlatformAdminBindingPage =
        await InstanceService.loadAdminBindings(this.appliedKeyword, 1, this.pageSize)
      if (requestId !== this.requestSequence) {
        return
      }
      this.page = 1
      this.accounts = result.list
      this.total = result.total
      this.expandedAccountKeys = this.retainExistingExpandedKeys(result.list)
    } catch (err) {
      if (requestId === this.requestSequence) {
        this.loadError = true
        this.showToast('加载华为账号绑定信息失败')
      }
    } finally {
      if (requestId === this.requestSequence) {
        this.loading = false
      }
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.accounts.length >= this.total) {
      return
    }
    const requestId: number = ++this.requestSequence
    const requestedKeyword: string = this.appliedKeyword
    this.loading = true
    this.loadError = false
    try {
      const nextPage: number = this.page + 1
      const result: PlatformAdminBindingPage =
        await InstanceService.loadAdminBindings(requestedKeyword, nextPage, this.pageSize)
      if (requestId !== this.requestSequence || requestedKeyword !== this.appliedKeyword) {
        return
      }
      this.accounts = this.mergeAccounts(this.accounts, result.list)
      this.page = nextPage
      this.total = result.total
    } catch (err) {
      if (requestId === this.requestSequence) {
        this.loadError = true
        this.showToast('加载更多绑定信息失败')
      }
    } finally {
      if (requestId === this.requestSequence) {
        this.loading = false
      }
    }
  }

  private submitSearch(): void {
    const nextKeyword: string = this.inputKeyword.trim()
    if (nextKeyword === this.appliedKeyword && !this.loadError) {
      return
    }
    this.appliedKeyword = nextKeyword
    this.refresh()
  }

  private mergeAccounts(current: PlatformAdminUser[], incoming: PlatformAdminUser[]): PlatformAdminUser[] {
    const result: PlatformAdminUser[] = []
    for (let index = 0; index < current.length; index++) {
      result.push(current[index])
    }
    for (let incomingIndex = 0; incomingIndex < incoming.length; incomingIndex++) {
      if (!this.containsAccount(result, incoming[incomingIndex].platformUserId)) {
        result.push(incoming[incomingIndex])
      }
    }
    return result
  }

  private containsAccount(items: PlatformAdminUser[], platformUserId: number): boolean {
    for (let index = 0; index < items.length; index++) {
      if (items[index].platformUserId === platformUserId) {
        return true
      }
    }
    return false
  }

  private toggleExpanded(item: PlatformAdminUser): void {
    const targetKey: string = this.getAccountKey(item)
    const nextKeys: string[] = []
    let removed: boolean = false
    for (let index = 0; index < this.expandedAccountKeys.length; index++) {
      if (this.expandedAccountKeys[index] === targetKey) {
        removed = true
      } else {
        nextKeys.push(this.expandedAccountKeys[index])
      }
    }
    if (!removed) {
      nextKeys.push(targetKey)
    }
    this.expandedAccountKeys = nextKeys
  }

  private isAccountExpanded(item: PlatformAdminUser): boolean {
    const targetKey: string = this.getAccountKey(item)
    for (let index = 0; index < this.expandedAccountKeys.length; index++) {
      if (this.expandedAccountKeys[index] === targetKey) {
        return true
      }
    }
    return false
  }

  private retainExistingExpandedKeys(items: PlatformAdminUser[]): string[] {
    const result: string[] = []
    for (let keyIndex = 0; keyIndex < this.expandedAccountKeys.length; keyIndex++) {
      const expandedKey: string = this.expandedAccountKeys[keyIndex]
      for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
        if (this.getAccountKey(items[itemIndex]) === expandedKey) {
          result.push(expandedKey)
          break
        }
      }
    }
    return result
  }

  private getAccountKey(item: PlatformAdminUser): string {
    return 'account:' + item.platformUserId.toString()
  }

  private getHuaweiAccountLabel(item: PlatformAdminUser): string {
    if (item.nickName !== '') {
      return item.nickName
    }
    if (item.bindings.length > 0 && item.bindings[0].localEmail !== '') {
      return item.bindings[0].localEmail
    }
    return '未命名账号'
  }

  private getHuaweiAccountDescription(item: PlatformAdminUser): string {
    if (item.bindings.length > 0 && item.bindings[0].localEmail !== '') {
      return '主邮箱：' + item.bindings[0].localEmail
    }
    return '暂未绑定主邮箱'
  }

  private getAvatarText(item: PlatformAdminUser): string {
    const fallbackEmail: string = item.bindings.length === 0 ? '' : item.bindings[0].localEmail
    const value: string = item.nickName === '' ? fallbackEmail : item.nickName
    return value === '' ? '华' : value.substring(0, 1).toUpperCase()
  }

  private getInstanceRoleLabel(role: string): string {
    if (role === 'INSTANCE_OWNER') {
      return '所有者'
    }
    if (role === 'INSTANCE_ADMIN') {
      return '管理员'
    }
    return '成员'
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1800 })
    } catch (err) {
      console.error('openToast failed')
    }
  }
}
