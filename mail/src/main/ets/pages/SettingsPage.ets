import { PromptAction } from '@kit.ArkUI'
import { bundleManager, common, ConfigurationConstant } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  BlurStrategy,
  HdsListItemCard,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  IconSize,
  PrefixIcon,
  SuffixTextAndArrow,
  hdsMaterial
} from '@kit.UIDesignKit'
import Constants from '../common/Constants'
import { HuaweiAccountApi, HuaweiAccountBinding } from '../api/HuaweiAccountApi'
import { setAppColorMode } from '../mailability/MailAbility'

class ChangeLogItem {
  version: string
  date: string
  changes: string[]

  constructor(version: string, date: string, changes: string[]) {
    this.version = version
    this.date = date
    this.changes = changes
  }
}

@Component
export struct SettingsPage {
  scroller: Scroller = new Scroller()
  @Prop topContentInset: number = Constants.TITLE_BAR_HEIGHT_MINI
  @StorageLink('authEmail') authEmail: string = ''
  @StorageLink('authRole') authRole: string = 'user'
  @StorageLink('authRoleName') authRoleName: string = '普通用户'
  @StorageLink('currentColorMode') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  @State showLogoutConfirm: boolean = false
  @State showThemeDialog: boolean = false
  @State showAboutSheet: boolean = false
  @State showChangeLogCover: boolean = false
  @State expandedChangeLogs: string[] = []
  @State huaweiNickName: string = ''
  @State huaweiAvatarUrl: string = ''
  @State huaweiPrimaryEmail: string = ''
  @State huaweiUserId: string = ''
  @State huaweiIdentityLoaded: boolean = false
  private readonly repositoryUrl: string = 'https://github.com/Riordon666/cloud-mail-for-harmonyos'
  private readonly telegramGroupUrl: string = 'https://t.me/CloudMailforHarmonyOSGroup'
  private readonly changeLogs: ChangeLogItem[] = [
    new ChangeLogItem('1.1.0', '2026.07.26', [
      '新增华为账号一键登录与主邮箱绑定',
      '新增管理员华为账号绑定查询与搜索',
      '个人设置展示华为账号头像、昵称、主邮箱和身份组',
      '完善登录安全与账号资料同步',
      '新增关于页面、官方社群入口与版本更新日志'
    ]),
    new ChangeLogItem('1.0.3', '2026.07.25', [
      '使用官方标题栏结构实现沉浸光感',
      '修复搜索邮件功能',
      '优化状态栏、标题栏和内容区间距'
    ]),
    new ChangeLogItem('1.0.2', '2026.07.21', [
      '新增收件箱下拉刷新',
      '修复星标状态实时刷新、取消星标和删除邮件',
      '完善个人设置身份组和主题显示'
    ]),
    new ChangeLogItem('1.0.1', '2026.07.21', [
      '更新云笺集应用名称与图标',
      '修复图文邮件显示',
      '优化邮件详情页悬浮工具栏'
    ]),
    new ChangeLogItem('1.0.0', '2026.07.11', [
      '首个公开测试版本',
      '支持收件箱、已发送、草稿箱和星标邮件',
      '支持邮件收发、账号管理与管理员功能'
    ])
  ]
  private toast: PromptAction = this.getUIContext().getPromptAction()
  onLogout?: () => void
  onManageAccounts?: () => void
  onSystemSettings?: () => void
  onManageUsers?: () => void
  onManageGlobalMails?: () => void
  onManageRoles?: () => void
  onOpenAnalytics?: () => void
  onManageRegistrationCodes?: () => void
  onManageHuaweiAccounts?: () => void

  aboutToAppear(): void {
    if (this.currentColorMode === undefined || this.currentColorMode === null) {
      this.currentColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    }
    this.loadHuaweiIdentity()
  }

  build() {
    Stack() {
      Scroll(this.scroller) {
        Column({ space: Constants.GAP_MEDIUM }) {
          Blank().height(this.topContentInset)

          Row({ space: Constants.GAP_MEDIUM }) {
            if (this.huaweiAvatarUrl !== '') {
              Image(this.huaweiAvatarUrl)
                .width(64)
                .height(64)
                .borderRadius(Constants.RADIUS_FULL)
                .objectFit(ImageFit.Cover)
            } else {
              Stack() {
                Circle()
                  .width(64)
                  .height(64)
                  .foregroundColor($r('app.color.primary_light'))
                Text(this.getHuaweiAvatarText())
                  .fontSize(28)
                  .fontColor($r('app.color.primary'))
              }
              .width(64)
              .height(64)
            }
            Column({ space: 6 }) {
              Text(this.getHuaweiDisplayName())
                .fontSize(Constants.FONT_SIZE_SUBTITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.getHuaweiBindingText())
                .fontSize(Constants.FONT_SIZE_SMALL)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: Constants.GAP_SMALL }) {
                Text('身份组 · ' + this.getRoleLabel())
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.tag_text'))
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .borderRadius(Constants.RADIUS_SMALL)
                  .backgroundColor(this.authRole === 'admin' ? $r('app.color.primary_light') : $r('app.color.info'))
                Text('华为账号已登录')
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(Constants.PADDING_EDGE)
          .borderRadius(Constants.RADIUS_CARD)
          .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK,
            { adaptiveColor: AdaptiveColor.DEFAULT })
          .border({ width: 1, color: $r('app.color.divider') })

          this.SectionTitle('账户与偏好')
          Column() {
            this.SettingsRow('账号管理', '主邮箱与副邮箱', '', $r('sys.symbol.person'), () => { this.openAccountManagement() })
            Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
            this.ThemeSettingsRow()
          }
          .width('100%')
          .borderRadius(Constants.RADIUS_CARD)
          .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK,
            { adaptiveColor: AdaptiveColor.DEFAULT })
          .border({ width: 1, color: $r('app.color.divider') })

          this.SectionTitle('隐私与支持')
          Column() {
            this.SettingsRow('隐私政策', '了解数据使用方式', '', $r('sys.symbol.lock_shield'), () => { this.openPrivacyPolicy() })
            Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
            this.SettingsRow('关于', '云笺集 · HarmonyOS 原生邮件客户端', this.getAppVersionLabel(),
              $r('sys.symbol.questionmark_circle'), () => {
                this.showAboutSheet = true
              })
          }
          .width('100%')
          .borderRadius(Constants.RADIUS_CARD)
          .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK,
            { adaptiveColor: AdaptiveColor.DEFAULT })
          .border({ width: 1, color: $r('app.color.divider') })

          if (this.authRole === 'admin') {
            this.SectionTitle('管理员专区')
            Column() {
              this.SettingsRow('系统设置', '网站与注册策略', '', $r('sys.symbol.gearshape'), () => { this.openSystemSettings() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('用户管理', '用户状态与角色', '', $r('sys.symbol.person'), () => { this.openUserManagement() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('全部邮件', '全局邮件管理', '', $r('sys.symbol.envelope'), () => { this.openGlobalMailManagement() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('角色权限', '角色与权限树', '', $r('sys.symbol.person_fill'), () => { this.openRoleManagement() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('数据分析', '平台数据概览', '', $r('sys.symbol.doc'), () => { this.openAnalytics() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('注册码管理', '生成与使用记录', '', $r('sys.symbol.star_fill'), () => { this.openRegistrationCodeManagement() })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.SettingsRow('华为账号绑定', '查看华为账号与主邮箱关系', '', $r('sys.symbol.person_2'), () => {
                this.openHuaweiAccountManagement()
              })
            }
            .width('100%')
            .borderRadius(Constants.RADIUS_CARD)
            .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK,
              { adaptiveColor: AdaptiveColor.DEFAULT })
            .border({ width: 1, color: $r('app.color.divider') })
          }

          Button('退出登录', { type: ButtonType.Capsule, stateEffect: true })
            .width('100%')
            .height(48)
            .fontSize(Constants.FONT_SIZE_SUBTITLE)
            .fontColor($r('app.color.danger'))
            .backgroundColor($r('app.color.card'))
            .margin({ top: Constants.GAP_SMALL })
            .onClick(() => { this.showLogoutConfirm = true })

          Blank().height(Constants.PADDING_TAB_CONTENT_BOTTOM)
        }
        .width('100%')
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 4, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('app.color.background'))

      if (this.showLogoutConfirm) {
        this.LogoutConfirmDialog()
      }

      if (this.showThemeDialog) {
        this.ThemeSelectDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .blur(this.showAboutSheet ? 12 : 0)
    .bindSheet($$this.showAboutSheet, this.AboutSheet(), {
      height: '84%',
      dragBar: false,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_THICK,
      maskColor: 0x1A000000,
      enableOutsideInteractive: false
    })
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(Constants.FONT_SIZE_SMALL)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 4, top: 4 })
  }

  @Builder
  private SettingsRow(title: string, description: string, value: string, icon: Resource, onItemClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(Constants.SIZE_ICON_MEDIUM)
        .fontColor([$r('app.color.text_primary')])
        .width(32)
        .margin({ right: 12 })

      Column({ space: 3 }) {
        Text(title)
          .fontSize(Constants.FONT_SIZE_SUBTITLE)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(description)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (value !== '') {
        Text(value)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 6 })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(Constants.SIZE_ICON_SMALL)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(68)
    .padding({ left: 16, right: 16 })
    .onClick(onItemClick)
  }

  @Builder
  private ThemeSettingsRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.paintbrush'))
        .fontSize(Constants.SIZE_ICON_MEDIUM)
        .fontColor([$r('app.color.text_primary')])
        .width(32)
        .margin({ right: 12 })

      Column({ space: 3 }) {
        Text('外观与主题')
          .fontSize(Constants.FONT_SIZE_SUBTITLE)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text('主题与显示模式')
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.getThemeLabel())
        .fontSize(Constants.FONT_SIZE_SMALL)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 6 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(Constants.SIZE_ICON_SMALL)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(68)
    .padding({ left: 16, right: 16 })
    .onClick(() => { this.showThemeDialog = true })
  }

  @Builder
  private SettingsCard(title: string, description: string, value: string, icon: ResourceStr, onItemClick: () => void) {
    HdsListItemCard({
      prefixItem: new PrefixIcon({
        iconSize: IconSize.SYSTEM_ICON,
        iconValue: { symbol: icon }
      }),
      textItem: {
        primaryText: { text: title },
        secondaryText: { text: description }
      },
      suffixItem: new SuffixTextAndArrow({ text: value }),
      cardHeight: 72,
      cardBackgroundColor: $r('app.color.card'),
      cardBorderRadius: Constants.RADIUS_CARD,
      onClick: onItemClick
    })
  }

  @Builder
  private AboutSheet() {
    HdsNavDestination() {
      Column() {
        Column({ space: Constants.GAP_SMALL }) {
          Image($r('app.media.startIcon'))
            .width(96)
            .height(96)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .shadow(Constants.SHADOW_CARD)

          Text('云笺集')
            .fontSize(Constants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text('版本 ' + this.getAppVersionName())
            .fontSize(Constants.FONT_SIZE_COMMON)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(176)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 32 })

        Row().height(12)

        Scroll() {
          Column({ space: Constants.GAP_MEDIUM }) {
            Column() {
              this.AboutActionRow('联系我', '2717831140@qq.com', '点击复制', () => {
                this.copyText('2717831140@qq.com', '联系邮箱')
              })
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
              this.AboutActionRow('QQ交流群', '1075732184', '点击复制', () => {
                this.copyText('1075732184', 'QQ群号')
              })
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
              this.AboutActionRow('官方TG交流群', 't.me/CloudMailforHarmonyOSGroup', '点击加入', () => {
                this.openTelegramGroup()
              })
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
              this.AboutActionRow('开源仓库', 'Riordon666/cloud-mail-for-harmonyos', '', () => {
                this.openRepository()
              })
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
              Row() {
                Text('更新日志')
                  .fontSize(Constants.FONT_SIZE_SUBTITLE)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text('查看全部版本')
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ right: 8 })
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(Constants.SIZE_ICON_SMALL)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.showChangeLogCover = true
              })
              .bindSheet($$this.showChangeLogCover, this.ChangeLogSheet(), {
                height: '84%',
                dragBar: false,
                showClose: false,
                blurStyle: BlurStyle.COMPONENT_THICK,
                maskColor: 0x1A000000,
                enableOutsideInteractive: false
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
            .border({ width: 1, color: $r('app.color.divider') })

            Text('云笺集 · HarmonyOS 原生邮件客户端')
              .fontSize(Constants.FONT_SIZE_SMALL)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 4, bottom: 24 })
          }
          .width('100%')
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: '关于' },
        backIcon: {
          label: '返回',
          icon: $r('sys.symbol.chevron_backward'),
          isEnabled: true,
          action: () => {
            this.showAboutSheet = false
          }
        },
        menu: {
          maxCount: 1,
          value: [{
            content: {
              label: '关闭',
              icon: $r('sys.symbol.xmark'),
              isEnabled: true,
              action: () => {
                this.showAboutSheet = false
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        blurStrategy: BlurStrategy.DISABLE,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
            blurRadius: 0
          },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onBackPressed(() => {
      this.showAboutSheet = false
      return true
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .blur(this.showChangeLogCover ? 12 : 0)
  }

  @Builder
  private AboutActionRow(title: string, value: string, hint: string, onItemClick: () => void) {
    Row() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(Constants.FONT_SIZE_SUBTITLE)
          .fontColor($r('app.color.text_primary'))
        Text(value)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (hint !== '') {
        Text(hint)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.primary'))
          .margin({ right: 8 })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(Constants.SIZE_ICON_SMALL)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .onClick(onItemClick)
  }

  @Builder
  private ChangeLogSheet() {
    HdsNavDestination() {
      Column() {
        Column({ space: Constants.GAP_MEDIUM }) {
          Image($r('app.media.startIcon'))
            .width(96)
            .height(96)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .shadow(Constants.SHADOW_CARD)

          Text('当前版本：' + this.getAppVersionName() + ' (' + this.getAppVersionCode().toString() + ')')
            .fontSize(Constants.FONT_SIZE_SUBTITLE)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(176)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 32 })

        Row().height(12)

        List({ space: Constants.GAP_MEDIUM }) {
          ForEach(this.changeLogs, (item: ChangeLogItem) => {
            ListItem() {
              this.ChangeLogCard(item)
            }
            .width('100%')
          }, (item: ChangeLogItem): string => item.version)

          ListItem() {
            Row().height(32)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
        .alignListItem(ListItemAlign.Center)
        .cachedCount(this.changeLogs.length)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: '更新日志' },
        backIcon: {
          label: '返回',
          icon: $r('sys.symbol.chevron_backward'),
          isEnabled: true,
          action: () => {
            this.showChangeLogCover = false
          }
        },
        menu: {
          maxCount: 1,
          value: [{
            content: {
              label: '关闭',
              icon: $r('sys.symbol.xmark'),
              isEnabled: true,
              action: () => {
                this.showChangeLogCover = false
                this.showAboutSheet = false
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        },
        blurStrategy: BlurStrategy.DISABLE,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
            blurRadius: 0
          },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        }
      }
    })
    .hideBackButton(false)
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onBackPressed(() => {
      this.showChangeLogCover = false
      return true
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ChangeLogCard(item: ChangeLogItem) {
    Column() {
      Row() {
        Text(item.version + '  ' + item.date)
          .fontSize(Constants.FONT_SIZE_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.isChangeLogExpanded(item.version) ?
          $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(Constants.SIZE_ICON_SMALL)
          .fontColor([$r('app.color.text_primary')])
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.toggleChangeLog(item.version)
      })

      if (this.isChangeLogExpanded(item.version)) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })
        Column({ space: 8 }) {
          ForEach(item.changes, (change: string) => {
            Row({ space: 8 }) {
              Circle()
                .width(5)
                .height(5)
                .foregroundColor($r('app.color.primary'))
                .margin({ top: 5 })
              Text(change)
                .fontSize(Constants.FONT_SIZE_COMMON)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 18 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  private isChangeLogExpanded(version: string): boolean {
    return this.expandedChangeLogs.includes(version)
  }

  private toggleChangeLog(version: string): void {
    if (this.isChangeLogExpanded(version)) {
      this.expandedChangeLogs = this.expandedChangeLogs.filter((item: string): boolean => item !== version)
      return
    }
    this.expandedChangeLogs = [...this.expandedChangeLogs, version]
  }

  @Builder
  private ThemeSelectDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => { this.showThemeDialog = false })

      Column({ space: 0 }) {
        Text('外观设置')
          .fontSize(Constants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 16 })

        this.ThemeOption('跟随系统', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
        this.ThemeOption('浅色模式', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
        this.ThemeOption('深色模式', ConfigurationConstant.ColorMode.COLOR_MODE_DARK)

        Button('取消', { type: ButtonType.Normal, stateEffect: true })
          .width('100%')
          .height(44)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.card'))
          .margin({ top: 12, left: 20, right: 20, bottom: 20 })
          .onClick(() => { this.showThemeDialog = false })
      }
      .width('100%')
      .margin({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
      .backgroundColor($r('app.color.card'))
      .borderRadius(Constants.RADIUS_CARD)
      .shadow(Constants.SHADOW_CARD)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ThemeOption(label: string, mode: number) {
    Row() {
      Text(label)
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.currentColorMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(Constants.SIZE_ICON_SMALL)
          .fontColor([$r('app.color.primary')])
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .onClick(() => { this.selectTheme(mode) })
  }

  @Builder
  private LogoutConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))

      Column({ space: Constants.GAP_MEDIUM }) {
        Text('确认退出登录')
          .fontSize(Constants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('退出后需要重新输入邮箱账号和密码才能进入邮箱。')
          .fontSize(Constants.FONT_SIZE_COMMON)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Row() {
          Button('取消', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.background'))
            .onClick(() => { this.showLogoutConfirm = false })
          Button('退出登录', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .fontColor($r('sys.color.icon_on_primary'))
            .backgroundColor($r('app.color.danger'))
            .margin({ left: Constants.GAP_MEDIUM })
            .onClick(() => { this.confirmLogout() })
        }
        .width('100%')
      }
      .width('100%')
      .margin({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
      .padding(20)
      .backgroundColor($r('app.color.card'))
      .borderRadius(Constants.RADIUS_CARD)
      .shadow(Constants.SHADOW_CARD)
    }
    .width('100%')
    .height('100%')
  }

  private getThemeLabel(): string {
    if (this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      return '浅色模式'
    }
    if (this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return '深色模式'
    }
    return '跟随系统'
  }

  private getRoleLabel(): string {
    const roleName: string = this.authRoleName.trim()
    if (roleName === 'admin') {
      return '管理员'
    }
    return roleName === '' ? '普通用户' : roleName
  }

  private getAppVersionLabel(): string {
    return 'v' + this.getAppVersionName()
  }

  private getAppVersionName(): string {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionName
    } catch (err) {
      console.error('get app version failed')
      return '1.1.0'
    }
  }

  private getAppVersionCode(): number {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionCode
    } catch (err) {
      console.error('get app version code failed')
      return 1010000
    }
  }

  private selectTheme(mode: number): void {
    this.showThemeDialog = false
    this.currentColorMode = mode
    setAppColorMode(mode)
  }

  private openAccountManagement(): void {
    if (this.onManageAccounts) {
      this.onManageAccounts()
    }
  }

  private openSystemSettings(): void {
    if (this.onSystemSettings) {
      this.onSystemSettings()
    }
  }

  private openUserManagement(): void {
    if (this.onManageUsers) {
      this.onManageUsers()
    }
  }

  private openGlobalMailManagement(): void {
    if (this.onManageGlobalMails) {
      this.onManageGlobalMails()
    }
  }

  private openRoleManagement(): void {
    if (this.onManageRoles) {
      this.onManageRoles()
    }
  }

  private openAnalytics(): void {
    if (this.onOpenAnalytics) {
      this.onOpenAnalytics()
    }
  }

  private openRegistrationCodeManagement(): void {
    if (this.onManageRegistrationCodes) {
      this.onManageRegistrationCodes()
    }
  }

  private openHuaweiAccountManagement(): void {
    if (this.onManageHuaweiAccounts) {
      this.onManageHuaweiAccounts()
    }
  }

  private async loadHuaweiIdentity(): Promise<void> {
    try {
      const binding: HuaweiAccountBinding | null = await HuaweiAccountApi.current()
      this.huaweiIdentityLoaded = true
      if (binding === null) {
        return
      }
      this.huaweiNickName = binding.nickName
      this.huaweiAvatarUrl = binding.avatarUrl
      this.huaweiPrimaryEmail = binding.primaryEmail
      this.huaweiUserId = binding.huaweiUserId
    } catch (err) {
      this.huaweiIdentityLoaded = true
      console.error('load Huawei identity failed')
    }
  }

  private getHuaweiDisplayName(): string {
    if (!this.huaweiIdentityLoaded) {
      return '正在读取华为账号'
    }
    if (this.huaweiNickName !== '') {
      return this.huaweiNickName
    }
    return this.huaweiUserId === '' ? '华为账号资料待更新' : '华为账号 · ' + this.huaweiUserId
  }

  private getHuaweiBindingText(): string {
    if (!this.huaweiIdentityLoaded) {
      return '正在读取绑定信息'
    }
    const email: string = this.huaweiPrimaryEmail === '' ? this.authEmail : this.huaweiPrimaryEmail
    return email === '' ? '暂未绑定主邮箱' : '绑定主邮箱：' + email
  }

  private getHuaweiAvatarText(): string {
    const value: string = this.huaweiNickName === '' ? this.authEmail : this.huaweiNickName
    return value === '' ? '华' : value.substring(0, 1).toUpperCase()
  }

  private async openPrivacyPolicy(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      await context.openLink(Constants.PRIVACY_POLICY_URL)
    } catch (err) {
      console.error('open privacy policy failed')
      this.showToast('暂时无法打开隐私政策')
    }
  }

  private async copyText(value: string, label: string): Promise<void> {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value)
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      await systemPasteboard.setData(data)
      this.showToast(label + '已复制')
    } catch (err) {
      console.error('copy text failed')
      this.showToast('复制失败，请重试')
    }
  }

  private async openRepository(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      await context.openLink(this.repositoryUrl)
    } catch (err) {
      console.error('open repository failed')
      this.showToast('暂时无法打开开源仓库')
    }
  }

  private async openTelegramGroup(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      await context.openLink(this.telegramGroupUrl)
    } catch (err) {
      console.error('open Telegram group failed')
      this.showToast('暂时无法打开官方TG交流群')
    }
  }

  private confirmLogout(): void {
    this.showLogoutConfirm = false
    if (this.onLogout) {
      this.onLogout()
    }
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 1500 })
    } catch (err) {
      console.error('openToast failed')
    }
  }
}
