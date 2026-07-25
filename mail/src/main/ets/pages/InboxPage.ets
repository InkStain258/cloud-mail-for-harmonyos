import Constants from '../common/Constants'
import { ApiException } from '../common/HttpClient'
import { MailDetailParams, MailItem } from '../common/MailModels'
import { MailPage, MailService } from '../common/MailService'
import { MailListDataSource } from '../common/MailListDataSource'
import { PromptAction } from '@kit.ArkUI'
import { EmailCard } from '../components/EmailCard'

@Component
export struct InboxPage {
  scroller: Scroller = new Scroller()
  @Prop topContentInset: number = Constants.INBOX_TOP_CONTENT_INSET
  private dataSource: MailListDataSource = new MailListDataSource()
  @StorageLink('mailRevision') @Watch('onMailRevision') mailRevision: number = 0
  @Link @Watch('onSearchTextUpdated') searchText: string
  @State emailList: MailItem[] = []
  @State isLoading: boolean = false
  @State isLoadingMore: boolean = false
  @State isRefreshing: boolean = false
  @State refreshStatus: RefreshStatus = RefreshStatus.Inactive
  @State hasMore: boolean = true
  @State refreshKey: number = 0
  private pathStack: NavPathStack = AppStorage.get('appPathStack') as NavPathStack
  private toast: PromptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.loadEmails()
  }

  private onMailRevision(): void {
    this.loadEmails(false)
  }

  private onSearchTextUpdated(): void {
    this.syncVisibleData()
  }

  private async loadEmails(showLoading: boolean = true, showSuccess: boolean = false): Promise<void> {
    if (showLoading) {
      this.isLoading = true
    }
    try {
      const page: MailPage = await MailService.loadInboxPage(0)
      this.emailList = page.items
      this.hasMore = this.emailList.length < page.total && page.items.length > 0
      this.syncVisibleData()
      if (showSuccess) {
        this.showToast('邮件已刷新')
      }
    } catch (err) {
      this.showRequestError(err)
    } finally {
      if (showLoading) {
        this.isLoading = false
      }
      this.isRefreshing = false
      this.refreshStatus = RefreshStatus.Inactive
    }
  }

  private async loadMoreEmails(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMore || this.searchText.trim() !== '' || this.emailList.length === 0) {
      return
    }
    this.isLoadingMore = true
    try {
      const cursor: number = this.emailList[this.emailList.length - 1].id
      const page: MailPage = await MailService.loadInboxPage(cursor)
      const appended: MailItem[] = this.removeLoadedItems(page.items)
      if (appended.length > 0) {
        const result: MailItem[] = []
        for (let index = 0; index < this.emailList.length; index++) {
          result.push(this.emailList[index])
        }
        for (let index = 0; index < appended.length; index++) {
          result.push(appended[index])
        }
        this.emailList = result
        this.dataSource.appendData(appended)
      }
      this.hasMore = page.items.length > 0 && this.emailList.length < page.total
    } catch (err) {
      this.showRequestError(err)
    } finally {
      this.isLoadingMore = false
    }
  }

  private removeLoadedItems(items: MailItem[]): MailItem[] {
    const result: MailItem[] = []
    for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
      let exists: boolean = false
      for (let loadedIndex = 0; loadedIndex < this.emailList.length; loadedIndex++) {
        if (items[itemIndex].id === this.emailList[loadedIndex].id) {
          exists = true
          break
        }
      }
      if (!exists) {
        result.push(items[itemIndex])
      }
    }
    return result
  }

  private getFiltered(): MailItem[] {
    const keyword: string = this.searchText.trim().toLowerCase()
    if (keyword === '') {
      return this.emailList
    }
    return this.emailList.filter((item: MailItem) =>
      item.name.toLowerCase().includes(keyword) ||
      item.email.toLowerCase().includes(keyword) ||
      item.subject.toLowerCase().includes(keyword)
    )
  }

  private syncVisibleData(): void {
    this.dataSource.setData(this.getFiltered())
  }

  private async markAsRead(id: number): Promise<void> {
    try {
      await MailService.markRead(id)
      this.replaceUnread(id, false)
    } catch (err) {
      this.showRequestError(err)
    }
  }

  private async toggleStar(id: number, starred: boolean): Promise<void> {
    const nextStarred: boolean = !starred
    try {
      await MailService.setStar(id, nextStarred)
      this.replaceStarred(id, nextStarred)
      this.showToast(nextStarred ? '已加入星标' : '已取消星标')
    } catch (err) {
      this.showRequestError(err)
    }
  }

  private async deleteEmail(id: number): Promise<void> {
    try {
      await MailService.delete(id)
      const result: MailItem[] = []
      for (let index = 0; index < this.emailList.length; index++) {
        if (this.emailList[index].id !== id) {
          result.push(this.emailList[index])
        }
      }
      this.emailList = result
      this.syncVisibleData()
      this.showToast('邮件已删除')
    } catch (err) {
      this.showRequestError(err)
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
                Text(this.searchText !== '' ? '未找到相关邮件' : '暂无邮件')
                  .fontSize(Constants.FONT_SIZE_SUBTITLE)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 12 })
              }
              .width('100%')
              .height(420)
              .justifyContent(FlexAlign.Center)
            }
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
            Column() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color($r('app.color.primary'))
                  .margin({ top: 12 })
              }
            }
            .width('100%')
            .height(Constants.PADDING_TAB_CONTENT_BOTTOM)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        .onReachEnd(() => { this.loadMoreEmails() })
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
