import Constants from '../common/Constants'
import { ApiException } from '../common/HttpClient'
import { MailDetailParams, MailItem } from '../common/MailModels'
import { MailService } from '../common/MailService'
import { MailHistoryKind, MailHistoryLoader } from '../common/MailHistoryLoader'
import { MailListDataSource } from '../common/MailListDataSource'
import { PromptAction } from '@kit.ArkUI'
import { EmailCard } from '../components/EmailCard'

@Component
export struct InboxPage {
  scroller: Scroller = new Scroller()
  @Prop topContentInset: number = Constants.INBOX_TOP_CONTENT_INSET
  private dataSource: MailListDataSource = new MailListDataSource()
  private history: MailHistoryLoader = new MailHistoryLoader(MailHistoryKind.Inbox)
  private operation: number = 0
  private searchTimer: number = -1
  private active: boolean = false
  @StorageLink('mailRevision') @Watch('onMailRevision') mailRevision: number = 0
  @StorageLink('sessionRevision') @Watch('onSessionChanged') sessionRevision: number = 0
  @Link @Watch('onSearchTextUpdated') searchText: string
  @State emailList: MailItem[] = []
  @State isLoading: boolean = false
  @State isLoadingMore: boolean = false
  @State isRefreshing: boolean = false
  @State refreshStatus: RefreshStatus = RefreshStatus.Inactive
  @State hasMore: boolean = true
  @State isSearching: boolean = false
  @State searchKeyword: string = ''
  @State loadFailed: boolean = false
  @State searchStalled: boolean = false
  @State refreshKey: number = 0
  private pathStack: NavPathStack = AppStorage.get('appPathStack') as NavPathStack
  private toast: PromptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.active = true
    this.searchKeyword = this.searchText.trim().toLowerCase()
    this.loadEmails()
  }

  aboutToDisappear(): void {
    this.active = false
    this.operation++
    this.history.cancel()
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
    }
  }

  private onSessionChanged(): void {
    if (this.active) {
      this.emailList = []
      this.syncVisibleData()
      this.loadEmails()
    }
  }

  private onMailRevision(): void {
    if (this.active) {
      this.loadEmails(false)
    }
  }

  private onSearchTextUpdated(): void {
    this.cancelSearch()
    this.searchKeyword = this.searchText.trim().toLowerCase()
    this.syncVisibleData()
    if (this.searchKeyword !== '' && this.active) {
      this.searchTimer = setTimeout(() => {
        this.searchTimer = -1
        this.loadEmails()
      }, 350)
    } else if (this.active) {
      this.loadEmails()
    }
  }

  private async loadEmails(showLoading: boolean = true, showSuccess: boolean = false): Promise<void> {
    this.cancelSearch()
    this.history.reset(this.searchKeyword !== '')
    this.hasMore = true
    this.searchStalled = false
    const operation: number = ++this.operation
    const scope: string = MailHistoryLoader.sessionKey()
    this.loadFailed = false
    if (showLoading) {
      this.isLoading = true
    }
    try {
      const applied: boolean = await this.history.loadNext()
      if (!applied || !this.isCurrent(operation, scope)) {
        return
      }
      this.syncHistory()
      if (showSuccess) {
        this.showToast('邮件已刷新')
      }
    } catch (err) {
      if (this.isCurrent(operation, scope)) {
        this.loadFailed = true
        this.showRequestError(err)
      }
    } finally {
      if (this.isCurrent(operation, scope)) {
        this.isLoading = false
        this.isRefreshing = false
        this.refreshStatus = RefreshStatus.Inactive
      }
    }
    if (this.isCurrent(operation, scope) && this.searchKeyword !== '' && !this.loadFailed) {
      this.searchHistory()
    }
  }

  private async loadMoreEmails(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || this.isSearching || !this.hasMore || this.searchKeyword !== '') {
      return
    }
    const operation: number = this.operation
    const scope: string = MailHistoryLoader.sessionKey()
    this.isLoadingMore = true
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
      if (this.isCurrent(operation, scope)) {
        this.isLoadingMore = false
      }
    }
  }

  private async searchHistory(): Promise<void> {
    if (this.isSearching || this.searchKeyword === '' || !this.active || !this.history.hasMore) {
      return
    }
    const operation: number = this.operation
    const scope: string = MailHistoryLoader.sessionKey()
    this.isSearching = true
    this.loadFailed = false
    try {
      // Search a bounded batch. Continuing is explicit, never an unbounded crawl.
      for (let pageIndex = 0; pageIndex < 3 && this.history.hasMore; pageIndex++) {
        if (!this.isCurrent(operation, scope) || !await this.history.loadNext()) {
          break
        }
        this.syncHistory()
      }
    } catch (err) {
      if (this.isCurrent(operation, scope)) {
        this.loadFailed = true
        this.showRequestError(err)
      }
    } finally {
      if (this.isCurrent(operation, scope)) {
        this.isSearching = false
      }
    }
  }

  private cancelSearch(): void {
    this.operation++
    this.history.cancel()
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.isSearching = false
    this.isLoading = false
    this.isLoadingMore = false
    this.isRefreshing = false
    this.refreshStatus = RefreshStatus.Inactive
  }

  private isCurrent(operation: number, scope: string): boolean {
    return this.active && operation === this.operation && scope === MailHistoryLoader.sessionKey()
  }

  private syncHistory(): void {
    this.emailList = this.history.items.slice()
    this.hasMore = this.history.hasMore
    this.searchStalled = this.history.stalled
    this.syncVisibleData()
  }

  private getFiltered(): MailItem[] {
    const keyword: string = this.searchKeyword
    if (keyword === '') {
      return this.emailList
    }
    return this.emailList.filter((item: MailItem) =>
      item.name.toLowerCase().includes(keyword) ||
      item.email.toLowerCase().includes(keyword) ||
      item.toEmail.toLowerCase().includes(keyword) ||
      item.subject.toLowerCase().includes(keyword) ||
      (item.detailLoaded && item.body.toLowerCase().includes(keyword))
    )
  }

  private syncVisibleData(): void {
    this.dataSource.setData(this.getFiltered())
  }

  private async markAsRead(id: number): Promise<void> {
    const scope: string = MailHistoryLoader.sessionKey()
    try {
      await MailService.markRead(id)
      if (!this.active || scope !== MailHistoryLoader.sessionKey()) { return }
      this.replaceUnread(id, false)
    } catch (err) {
      if (this.active && scope === MailHistoryLoader.sessionKey()) { this.showRequestError(err) }
    }
  }

  private async toggleStar(id: number, starred: boolean): Promise<void> {
    const scope: string = MailHistoryLoader.sessionKey()
    const nextStarred: boolean = !starred
    try {
      await MailService.setStar(id, nextStarred)
      if (!this.active || scope !== MailHistoryLoader.sessionKey()) { return }
      this.replaceStarred(id, nextStarred)
      this.showToast(nextStarred ? '已加入星标' : '已取消星标')
    } catch (err) {
      if (this.active && scope === MailHistoryLoader.sessionKey()) { this.showRequestError(err) }
    }
  }

  private async deleteEmail(id: number): Promise<void> {
    const scope: string = MailHistoryLoader.sessionKey()
    try {
      await MailService.delete(id)
      if (!this.active || scope !== MailHistoryLoader.sessionKey()) { return }
      const result: MailItem[] = []
      for (let index = 0; index < this.emailList.length; index++) {
        if (this.emailList[index].id !== id) {
          result.push(this.emailList[index])
        }
      }
      this.emailList = result
      this.history.replaceItems(result)
      this.syncVisibleData()
      this.showToast('邮件已删除')
    } catch (err) {
      if (this.active && scope === MailHistoryLoader.sessionKey()) { this.showRequestError(err) }
    }
  }

  private openDetail(item: MailItem, index: number): void {
    if (item.unread) {
      this.markAsRead(item.id)
    }
    const filtered: MailItem[] = this.getFiltered()
    const params: MailDetailParams = new MailDetailParams(item, filtered, index)
    this.pathStack.pushPathByName('DetailPage', params)
  }

  private replaceUnread(id: number, unread: boolean): void {
    const result: MailItem[] = []
    for (let index = 0; index < this.emailList.length; index++) {
      const source: MailItem = this.emailList[index]
      const next: MailItem = source.copy()
      if (next.id === id) {
        next.unread = unread
      }
      result.push(next)
    }
    this.emailList = result
    this.history.replaceItems(result)
    this.syncVisibleData()
    this.refreshKey++
  }

  private replaceStarred(id: number, starred: boolean): void {
    const result: MailItem[] = []
    for (let index = 0; index < this.emailList.length; index++) {
      const source: MailItem = this.emailList[index]
      const next: MailItem = source.copy()
      if (next.id === id) {
        next.starred = starred
      }
      result.push(next)
    }
    this.emailList = result
    this.history.replaceItems(result)
    this.syncVisibleData()
    this.refreshKey++
  }

  private showRequestError(err: Error): void {
    if (err instanceof ApiException) {
      this.showToast(err.message)
      return
    }
    this.showToast('请求失败，请稍后重试')
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1500 })
    } catch (err) {
      console.error('openToast failed')
    }
  }

  @Builder
  private HistoryFooter() {
    Column({ space: 8 }) {
      if (this.searchKeyword !== '') {
        Text($r('app.string.mail_history_scope', this.emailList.length))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        if (this.isSearching) {
          Row({ space: 8 }) {
            LoadingProgress().width(20).height(20).color($r('app.color.primary'))
            Text($r('app.string.mail_history_searching'))
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.text_secondary'))
          }
          Button($r('app.string.mail_history_cancel'))
            .onClick(() => { this.cancelSearch() })
        } else if (this.searchStalled) {
          Text($r('app.string.mail_history_stalled'))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.hasMore) {
          if (this.loadFailed) {
            Text($r('app.string.mail_history_load_failed'))
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.text_secondary'))
          }
          Button($r('app.string.mail_history_continue'))
            .onClick(() => { this.searchHistory() })
        } else {
          Text($r('app.string.mail_history_finished'))
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
        }
      } else if (this.isLoadingMore) {
        LoadingProgress().width(24).height(24).color($r('app.color.primary'))
      } else if (this.searchStalled) {
        Text($r('app.string.mail_history_stalled'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.loadFailed) {
        Text($r('app.string.mail_history_load_failed'))
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
        Button($r('app.string.mail_history_retry'))
          .onClick(() => {
            if (this.emailList.length === 0) {
              this.loadEmails()
            } else {
              this.loadMoreEmails()
            }
          })
      } else if (this.hasMore) {
        Button($r('app.string.mail_history_load_more'))
          .onClick(() => { this.loadMoreEmails() })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: Constants.PADDING_TAB_CONTENT_BOTTOM })
  }

  @Builder
  private RefreshIndicator() {
    Stack() {
      if (this.refreshStatus === RefreshStatus.Drag || this.refreshStatus === RefreshStatus.OverDrag ||
        this.refreshStatus === RefreshStatus.Refresh) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.primary'))
          Text(this.refreshStatus === RefreshStatus.Refresh ? '正在刷新邮件' : '下拉刷新邮件')
            .fontSize(Constants.FONT_SIZE_SMALL)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(36)
        .justifyContent(FlexAlign.Center)
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
          Text('正在加载邮件…')
            .fontSize(Constants.FONT_SIZE_SUBTITLE)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topContentInset })
        .justifyContent(FlexAlign.Center)
      } else if (this.getFiltered().length === 0) {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.RefreshIndicator() }) {
          List({ scroller: this.scroller }) {
            ListItem() {
              Column().height(this.topContentInset)
            }
            ListItem() {
              Column() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(48)
                  .fontColor([$r('app.color.text_tertiary')])
                Text(this.searchKeyword !== '' ? (this.hasMore || this.searchStalled || this.loadFailed ?
                  $r('app.string.mail_history_partial_empty') : $r('app.string.mail_history_complete_empty')) :
                  (this.loadFailed ? $r('app.string.mail_history_load_failed') : '暂无邮件'))
                  .fontSize(Constants.FONT_SIZE_SUBTITLE)
                  .fontColor($r('app.color.text_tertiary'))
                  .textAlign(TextAlign.Center)
                  .margin({ top: 12 })
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            }
            ListItem() { this.HistoryFooter() }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        }
        .width('100%')
        .height('100%')
        .pullToRefresh(true)
        .refreshOffset(64)
        .onStateChange((status: RefreshStatus) => { this.refreshStatus = status })
        .onRefreshing(() => { this.loadEmails(false, true) })
      } else {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.RefreshIndicator() }) {
          List({ scroller: this.scroller }) {
          ListItem() {
            Column().height(this.topContentInset)
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
                builder: () => { this.SwipeActions(item.id, item.unread, item.starred) },
                actionAreaDistance: 180
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (item: MailItem): string => item.id.toString() + '_' + item.unread.toString() + '_' + item.starred.toString() + '_' + this.refreshKey.toString())
          ListItem() {
            this.HistoryFooter()
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        .onReachEnd(() => {
          if (!this.loadFailed) { this.loadMoreEmails() }
        })
        }
        .width('100%')
        .height('100%')
        .pullToRefresh(true)
        .refreshOffset(64)
        .onStateChange((status: RefreshStatus) => { this.refreshStatus = status })
        .onRefreshing(() => { this.loadEmails(false, true) })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder SwipeActions(id: number, unread: boolean, starred: boolean) {
    Row() {
      if (unread) {
        Button() {
          Column() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(20)
              .fontColor([Color.White])
            Text('已读')
              .fontSize(12)
              .fontColor(Color.White)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width(60)
        .height('100%')
        .backgroundColor($r('app.color.success'))
        .onClick(() => { this.markAsRead(id) })
      }

      Button() {
        Column() {
          SymbolGlyph(starred ? $r('sys.symbol.star_slash') : $r('sys.symbol.star'))
            .fontSize(20)
            .fontColor([Color.White])
          Text(starred ? '取消标' : '星标')
            .fontSize(12)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(60)
      .height('100%')
      .backgroundColor(starred ? $r('app.color.text_tertiary') : $r('app.color.warning'))
      .onClick(() => { this.toggleStar(id, starred) })

      Button() {
        Column() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([Color.White])
          Text('删除')
            .fontSize(12)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(60)
      .height('100%')
      .backgroundColor($r('app.color.danger'))
      .onClick(() => { this.deleteEmail(id) })
    }
    .height('100%')
  }
}
