import Constants from '../common/Constants'
import { ApiException } from '../common/HttpClient'
import { MailDetailParams, MailItem } from '../common/MailModels'
import { MailService } from '../common/MailService'
import { MailHistoryKind, MailHistoryLoader } from '../common/MailHistoryLoader'
import { MailListDataSource } from '../common/MailListDataSource'
import { PromptAction } from '@kit.ArkUI'
import { EmailCard } from '../components/EmailCard'
import { EmptyState } from '../components/EmptyState'
import { MailHistoryFooter } from '../components/MailHistoryFooter'

@Component
export struct StarredPage {
  scroller: Scroller = new Scroller()
  @Prop topContentInset: number = Constants.TITLE_BAR_HEIGHT_MINI
  private dataSource: MailListDataSource = new MailListDataSource()
  private history: MailHistoryLoader = new MailHistoryLoader(MailHistoryKind.Starred)
  private operation: number = 0
  private active: boolean = false
  private pathStack: NavPathStack = AppStorage.get('appPathStack') as NavPathStack
  private toast: PromptAction = this.getUIContext().getPromptAction()
  @StorageLink('mailRevision') @Watch('onMailRevision') mailRevision: number = 0
  @StorageLink('sessionRevision') @Watch('onSessionChanged') sessionRevision: number = 0
  @State starList: MailItem[] = []
  @State isLoading: boolean = false
  @State loadingMore: boolean = false
  @State hasMore: boolean = true
  @State loadFailed: boolean = false
  @State stalled: boolean = false
  @State refreshing: boolean = false
  @State refreshStatus: RefreshStatus = RefreshStatus.Inactive

  aboutToAppear(): void {
    this.active = true
    this.loadStarredEmails()
  }

  aboutToDisappear(): void {
    this.active = false
    this.operation++
    this.history.cancel()
  }

  private onSessionChanged(): void {
    if (this.active) {
      this.starList = []
      this.dataSource.setData([])
      this.loadStarredEmails()
    }
  }

  private onMailRevision(): void {
    if (this.active) { this.loadStarredEmails(false) }
  }

  private async loadStarredEmails(showLoading: boolean = true): Promise<void> {
    this.history.reset()
    this.hasMore = true
    this.stalled = false
    const operation: number = ++this.operation
    const scope: string = MailHistoryLoader.sessionKey()
    this.loadingMore = false
    this.loadFailed = false
    if (showLoading) {
      this.isLoading = true
    }
    try {
      if (await this.history.loadNext() && this.isCurrent(operation, scope)) {
        this.syncHistory()
      }
    } catch (err) {
      if (this.isCurrent(operation, scope)) {
        this.loadFailed = true
        this.showRequestError(err)
      }
    } finally {
      if (this.isCurrent(operation, scope)) {
        this.isLoading = false
        this.refreshing = false
        this.refreshStatus = RefreshStatus.Inactive
      }
    }
  }

  private async loadMore(): Promise<void> {
    if (this.isLoading || this.loadingMore || !this.hasMore) { return }
    const operation: number = this.operation
    const scope: string = MailHistoryLoader.sessionKey()
    this.loadingMore = true
    this.loadFailed = false
    try {
      if (await this.history.loadNext() && this.isCurrent(operation, scope)) {
        this.syncHistory()
      }
    } catch (err) {
      if (this.isCurrent(operation, scope)) {
        this.loadFailed = true
        this.showRequestError(err)
      }
    } finally {
      if (this.isCurrent(operation, scope)) { this.loadingMore = false }
    }
  }

  private isCurrent(operation: number, scope: string): boolean {
    return this.active && operation === this.operation && scope === MailHistoryLoader.sessionKey()
  }

  private syncHistory(): void {
    this.starList = this.history.items.slice()
    this.hasMore = this.history.hasMore
    this.stalled = this.history.stalled
    this.dataSource.setData(this.starList)
  }

  private openDetail(item: MailItem, index: number): void {
    const params: MailDetailParams = new MailDetailParams(item, this.starList, index)
    this.pathStack.pushPathByName('DetailPage', params)
  }

  private async cancelStar(id: number): Promise<void> {
    const scope: string = MailHistoryLoader.sessionKey()
    try {
      await MailService.setStar(id, false)
      if (!this.active || scope !== MailHistoryLoader.sessionKey()) { return }
      const result: MailItem[] = []
      for (let index = 0; index < this.starList.length; index++) {
        if (this.starList[index].id !== id) {
          result.push(this.starList[index])
        }
      }
      this.starList = result
      this.history.replaceItems(result)
      this.dataSource.removeItem(id)
      this.showToast('已取消星标')
    } catch (err) {
      if (this.active && scope === MailHistoryLoader.sessionKey()) { this.showRequestError(err) }
    }
  }

  private showRequestError(err: Error): void {
    const message: string = err instanceof ApiException ? err.message : '请求失败，请稍后重试'
    this.showToast(message)
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1500 })
    } catch (err) {
      console.error('openToast failed')
    }
  }

  @Builder
  private RefreshIndicator() {
    Stack() {
      if (this.refreshStatus === RefreshStatus.Drag || this.refreshStatus === RefreshStatus.OverDrag ||
        this.refreshStatus === RefreshStatus.Refresh) {
        LoadingProgress().width(24).height(24).color($r('app.color.primary'))
      }
    }
    .width('100%')
    .height(36)
    .translate({ y: this.topContentInset })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isLoading) {
        Column() {
          EmptyState({ icon: $r('sys.symbol.star'), message: '正在加载邮件…' })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topContentInset })
      } else {
        Refresh({ refreshing: $$this.refreshing, builder: this.RefreshIndicator() }) {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column().height(this.topContentInset)
          }
          if (this.starList.length === 0 && !this.loadFailed) {
            ListItem() {
              Column() {
                EmptyState({ icon: $r('sys.symbol.star'), message: '暂无星标邮件' })
              }.width('100%').height(200)
            }
          }
          LazyForEach(this.dataSource, (item: MailItem, index: number) => {
            ListItem() {
              EmailCard({
                name: item.name,
                subject: item.subject,
                time: item.time,
                unread: item.unread,
                verificationCode: item.verificationCode,
                onCardClick: () => { this.openDetail(item, index) }
              })
            }
            .swipeAction({
              end: {
                builder: () => { this.StarSwipeAction(item.id) },
                actionAreaDistance: 80
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (item: MailItem): string => item.id.toString())
          ListItem() {
            MailHistoryFooter({
              loading: this.loadingMore, failed: this.loadFailed, hasMore: this.hasMore, stalled: this.stalled,
              onLoad: () => {
                if (this.starList.length === 0) { this.loadStarredEmails() } else { this.loadMore() }
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        .onReachEnd(() => { if (!this.loadFailed) { this.loadMore() } })
        }
        .width('100%')
        .height('100%')
        .onStateChange((status: RefreshStatus) => { this.refreshStatus = status })
        .onRefreshing(() => { this.loadStarredEmails(false) })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder StarSwipeAction(id: number) {
    Row() {
      Button() {
        Column() {
          SymbolGlyph($r('sys.symbol.star_slash'))
            .fontSize(20)
            .fontColor([Color.White])
          Text('取消星标')
            .fontSize(12)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(80)
      .height('100%')
      .backgroundColor($r('app.color.warning'))
      .onClick(() => { this.cancelStar(id) })
    }
    .height('100%')
  }
}
