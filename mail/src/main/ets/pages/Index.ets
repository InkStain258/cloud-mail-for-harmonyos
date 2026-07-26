import { hdsMaterial, HdsTabs, HdsTabsController } from "@kit.UIDesignKit"
import { HdsNavigation } from "@kit.UIDesignKit"
import { HdsNavigationTitleMode, ScrollEffectType } from "@kit.UIDesignKit"
import { LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI"

import { InboxPage } from "./InboxPage"
import { SentPage } from "./SentPage"
import { DraftsPage } from "./DraftsPage"
import { StarredPage } from "./StarredPage"
import { SettingsPage } from "./SettingsPage"
import { DetailPageContent } from "./DetailPage"
import { ComposePageContent, ComposeParams } from "./ComposePage"
import { MailDetailParams } from '../common/MailModels'
import { AuthService } from "../common/AuthService"
import { AuthPage } from "./AuthPage"
import { AccountsPage } from "./AccountsPage"
import { SystemSettingsPage } from "./SystemSettingsPage"
import { UserManagementPage } from "./UserManagementPage"
import { GlobalMailPage } from "./GlobalMailPage"
import { RoleManagementPage } from "./RoleManagementPage"
import { AnalyticsPage } from "./AnalyticsPage"
import { RegistrationCodePage } from "./RegistrationCodePage"
import { HuaweiAccountManagementPage } from "./HuaweiAccountManagementPage"
import { NotFoundPage } from "./NotFoundPage"
import { SplashPage } from "./SplashPage"
import Constants from "../common/Constants"

@Entry
@Component
struct Index {
  @State currentTab: number = 0
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('safeAreaTopPx') safeAreaTopPx: number = 0
  @StorageLink('safeAreaBottomPx') safeAreaBottomPx: number = 0
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @State showSplash: boolean = true
  @State inboxSearchText: string = ''
  @State isInboxSearchFocused: boolean = false
  private tabController: HdsTabsController = new HdsTabsController()
  private inboxSearchController: SearchController = new SearchController()
  private pathStack: NavPathStack = new NavPathStack()
  private inboxScroller: Scroller = new Scroller()
  private sentScroller: Scroller = new Scroller()
  private draftsScroller: Scroller = new Scroller()
  private starredScroller: Scroller = new Scroller()
  private settingsScroller: Scroller = new Scroller()
  private isHomePrepared: boolean = false

  aboutToAppear(): void {
    AppStorage.setOrCreate("appPathStack", this.pathStack)
    if (this.authToken !== '') {
      this.restoreSession()
    }
  }

  private async restoreSession(): Promise<void> {
    const result = await AuthService.refreshSession()
    if (result.success && this.authToken !== '') {
      this.prepareHome()
    }
  }

  private prepareHome(): void {
    if (this.isHomePrepared) {
      return
    }
    this.isHomePrepared = true
    try {
      this.tabController.preloadItems([0, 1, 2, 3, 4])
    } catch (err) {
      console.error("init failed")
    }
  }

  build() {
    Stack() {
    if (this.authToken === '') {
      AuthPage({
        onAuthenticated: () => {
          this.currentTab = 0
          this.prepareHome()
        }
      })
    } else {
      HdsNavigation(this.pathStack) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        HdsTabs({ controller: this.tabController, index: this.currentTab }) {
          TabContent() {
            InboxPage({
              scroller: this.inboxScroller,
              searchText: $inboxSearchText,
              topContentInset: this.getInboxTopContentInset()
            })
          }
            .tabBar(new BottomTabBarStyle({
              normal: new SymbolGlyphModifier($r("sys.symbol.envelope"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("sys.color.font_secondary")]),
              selected: new SymbolGlyphModifier($r("sys.symbol.envelope_fill"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("app.color.primary")])
            }, "收件箱"))

          TabContent() {
            SentPage({
              scroller: this.sentScroller,
              topContentInset: this.getHomeTitleContentInset()
            })
          }
            .tabBar(new BottomTabBarStyle({
              normal: new SymbolGlyphModifier($r("sys.symbol.paperplane"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("sys.color.font_secondary")]),
              selected: new SymbolGlyphModifier($r("sys.symbol.paperplane_fill"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("app.color.primary")])
            }, "已发送"))

          TabContent() {
            DraftsPage({
              scroller: this.draftsScroller,
              topContentInset: this.getHomeTitleContentInset()
            })
          }
            .tabBar(new BottomTabBarStyle({
              normal: new SymbolGlyphModifier($r("sys.symbol.doc"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("sys.color.font_secondary")]),
              selected: new SymbolGlyphModifier($r("sys.symbol.doc"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("app.color.primary")])
            }, "草稿箱"))

          TabContent() {
            StarredPage({
              scroller: this.starredScroller,
              topContentInset: this.getHomeTitleContentInset()
            })
          }
            .tabBar(new BottomTabBarStyle({
              normal: new SymbolGlyphModifier($r("sys.symbol.star"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("sys.color.font_secondary")]),
              selected: new SymbolGlyphModifier($r("sys.symbol.star_fill"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("app.color.primary")])
            }, "星标邮件"))

          TabContent() {
            SettingsPage({
              scroller: this.settingsScroller,
              topContentInset: this.getHomeTitleContentInset(),
              onLogout: () => { this.logout() },
              onManageAccounts: () => { this.pathStack.pushPathByName('AccountsPage', undefined) },
              onSystemSettings: () => { this.pathStack.pushPathByName('SystemSettingsPage', undefined) },
              onManageUsers: () => { this.pathStack.pushPathByName('UserManagementPage', undefined) },
              onManageGlobalMails: () => { this.pathStack.pushPathByName('GlobalMailPage', undefined) },
              onManageRoles: () => { this.pathStack.pushPathByName('RoleManagementPage', undefined) },
              onOpenAnalytics: () => { this.pathStack.pushPathByName('AnalyticsPage', undefined) },
              onManageRegistrationCodes: () => { this.pathStack.pushPathByName('RegistrationCodePage', undefined) },
              onManageHuaweiAccounts: () => {
                this.pathStack.pushPathByName('HuaweiAccountManagementPage', undefined)
              }
            })
          }
            .tabBar(new BottomTabBarStyle({
              normal: new SymbolGlyphModifier($r("sys.symbol.person"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("sys.color.font_secondary")]),
              selected: new SymbolGlyphModifier($r("sys.symbol.person_fill"))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([$r("app.color.primary")])
            }, "个人设置"))
        }
        .scrollable(false)
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          barBottomMargin: 28,
          adaptToHandedness: true,
          lightColor: $r("app.color.primary"),
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onChange((index: number) => {
          this.currentTab = index
          if (index === 4) {
            this.refreshUserIdentity()
          }
        })
        .width("100%")
        .height("100%")

        Row() {
          SymbolGlyph($r("sys.symbol.square_and_pencil_fill"))
            .fontColor([$r("sys.color.icon_on_primary")])
            .fontSize($r("sys.float.Title_M"))
        }
        .backgroundColor($r("sys.color.background_emphasize"))
        .borderRadius("50%")
        .clip(true)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width(56)
        .aspectRatio(1)
        .margin({ right: 16, bottom: 108 })
        .onClick(() => {
          this.pathStack.pushPathByName("ComposePage", undefined)
        })
      }
      .width("100%")
      .height("100%")
      .padding({
        bottom: this.getUIContext().px2vp(this.safeAreaBottomPx)
      })
      .backgroundColor($r("app.color.background"))
    }
    .navDestination(this.navDestinationBuilder)
    .titleBar({
      content: {
        title: { mainTitle: this.getCurrentTitle() },
        bottomBuilder: { builder: (): void => this.TitleBottomBuilder() }
      },
      avoidLayoutSafeArea: true,
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
          backgroundStyle: {
            maskExtraHeight: this.currentTab === 0 ? Constants.SEARCH_BLUR_MASK_EXTRA_HEIGHT : 0
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            maskExtraHeight: this.currentTab === 0 ? Constants.SEARCH_BLUR_MASK_EXTRA_HEIGHT : 0
          }
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([
      this.inboxScroller,
      this.sentScroller,
      this.draftsScroller,
      this.starredScroller,
      this.settingsScroller
    ])
    .hideToolBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .width("100%")
      .height("100%")
      .backgroundColor($r("app.color.background"))
    }

    // 应用内闪屏覆盖层：蓝底 + 半屏大图标，淡出后移除
    if (this.showSplash) {
      SplashPage({
        onSplashFinished: () => {
          this.showSplash = false
        }
      })
    }
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("app.color.background"))
  }

  private logout(): void {
    AuthService.logout()
    this.currentTab = 0
  }

  private async refreshUserIdentity(): Promise<void> {
    await AuthService.refreshSession()
  }

  private getCurrentTitle(): string {
    const titles: string[] = ['收件箱', '已发送', '草稿箱', '星标邮件', '个人设置']
    return titles[this.currentTab]
  }

  private getHomeTitleContentInset(): number {
    return this.getUIContext().px2vp(this.safeAreaTopPx) + Constants.TITLE_BAR_HEIGHT_MINI
  }

  private getInboxTopContentInset(): number {
    return this.getUIContext().px2vp(this.safeAreaTopPx) + Constants.INBOX_TOP_CONTENT_INSET
  }

  @Builder
  private TitleBottomBuilder() {
    if (this.currentTab === 0) {
      Column() {
        Search({
          value: this.inboxSearchText,
          placeholder: '搜索邮件',
          controller: this.inboxSearchController
        })
          .searchIcon({ src: $r('sys.media.ohos_ic_public_search_filled'), size: 20 })
          .cancelButton({
            style: CancelButtonStyle.INPUT,
            icon: { size: 18, color: $r('app.color.text_tertiary'), src: '' }
          })
          .placeholderColor($r('app.color.text_tertiary'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .border({
            width: this.isInboxSearchFocused ? 1 : 0.5,
            color: this.isInboxSearchFocused ? $r('app.color.primary') : $r('app.color.divider')
          })
          .borderRadius(Constants.RADIUS_BUTTON)
          .height(48)
          .margin({
            left: Constants.PADDING_EDGE,
            right: Constants.PADDING_EDGE,
            top: 4,
            bottom: 8
          })
          .animation({ duration: Constants.DURATION_NORMAL, curve: Curve.EaseOut })
          .onChange((value: string) => {
            this.inboxSearchText = value
          })
          .onFocus(() => {
            this.isInboxSearchFocused = true
          })
          .onBlur(() => {
            this.isInboxSearchFocused = false
          })
      }
      .width('100%')
      .height(Constants.SEARCH_TITLE_BAR_HEIGHT)
    }
  }

  @Builder
  navDestinationBuilder(name: string, param: Object) {
    if (name === "DetailPage") {
      DetailPageContent({ emailData: param as MailDetailParams })
    } else if (name === "ComposePage") {
      if (param instanceof ComposeParams) {
        ComposePageContent({ composeParams: param })
      } else {
        ComposePageContent()
      }
    } else if (name === 'AccountsPage') {
      AccountsPage()
    } else if (name === 'SystemSettingsPage') {
      SystemSettingsPage()
    } else if (name === 'UserManagementPage') {
      UserManagementPage()
    } else if (name === 'GlobalMailPage') {
      GlobalMailPage()
    } else if (name === 'RoleManagementPage') {
      RoleManagementPage()
    } else if (name === 'AnalyticsPage') {
      AnalyticsPage()
    } else if (name === 'RegistrationCodePage') {
      RegistrationCodePage()
    } else if (name === 'HuaweiAccountManagementPage') {
      HuaweiAccountManagementPage()
    } else {
      NotFoundPage()
    }
  }
}
