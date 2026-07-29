import { PromptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  BlurStrategy,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  hdsMaterial
} from '@kit.UIDesignKit'
import { HuaweiAccountApi, HuaweiAccountBinding } from '../api/HuaweiAccountApi'
import { ProfileApi } from '../api/ProfileApi'
import Constants from '../common/Constants'
import { DateTimeUtils } from '../common/DateTimeUtils'
import { HuaweiAccountCache } from '../common/HuaweiAccountCache'

@Component
export struct AccountCenterSheetHost {
  @Link @Watch('onSheetVisibilityChanged') isShown: boolean
  @StorageLink('authEmail') authEmail: string = ''
  @State huaweiNickName: string = ''
  @State huaweiAvatarUrl: string = ''
  @State huaweiPrimaryEmail: string = ''
  @State huaweiUserId: string = ''
  @State userCreateTime: string = ''
  @State receiveMailCount: number = 0
  @State sentMailCount: number = 0
  @State starMailCount: number = 0
  @State identityLoaded: boolean = false
  @State showAccountSettings: boolean = false
  @State showPasswordDialog: boolean = false
  @State showDeleteAccountDialog: boolean = false
  @State showLogoutConfirm: boolean = false
  @State profileSubmitting: boolean = false
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  private toast: PromptAction = this.getUIContext().getPromptAction()
  onManageAccounts?: () => void
  onLogout?: () => void
  onIdentityChanged?: (avatarUrl: string, avatarText: string) => void

  aboutToAppear(): void {
    this.loadHuaweiIdentity()
  }

  private onSheetVisibilityChanged(): void {
    if (this.isShown) {
      this.loadHuaweiIdentity()
    }
  }

  build() {
    Row()
      .width(1)
      .height(1)
      .bindSheet($$this.isShown, this.AccountCenterSheet(), {
        height: '84%',
        dragBar: false,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_THICK,
        maskColor: 0x1A000000,
        enableOutsideInteractive: false
      })
  }

  @Builder
  private AccountCenterSheet() {
    Stack() {
      HdsNavDestination() {
        Scroll() {
          Column({ space: Constants.GAP_MEDIUM }) {
            Blank()
              .height(Constants.TITLE_BAR_HEIGHT_MINI + 2)

            Column({ space: 6 }) {
              if (this.huaweiAvatarUrl !== '') {
                Image(this.huaweiAvatarUrl)
                  .width(88)
                  .height(88)
                  .borderRadius(Constants.RADIUS_FULL)
                  .objectFit(ImageFit.Cover)
                  .shadow(Constants.SHADOW_CARD)
              } else {
                Stack() {
                  Circle()
                    .width(88)
                    .height(88)
                    .foregroundColor($r('app.color.primary_light'))
                  Text(this.getHuaweiAvatarText())
                    .fontSize(34)
                    .fontColor($r('app.color.primary'))
                }
                .width(88)
                .height(88)
              }
              Text(this.getHuaweiDisplayName())
                .fontSize(Constants.FONT_SIZE_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.getPrimaryEmailLabel())
                .fontSize(Constants.FONT_SIZE_COMMON)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ bottom: 8 })

            Grid() {
              GridItem() {
                this.AccountStatCard('注册时间', this.getRegistrationTime(), $r('sys.symbol.clock'))
              }
              GridItem() {
                this.AccountStatCard('收到邮件', this.receiveMailCount.toString(), $r('sys.symbol.envelope'))
              }
              GridItem() {
                this.AccountStatCard('发送邮件', this.sentMailCount.toString(), $r('sys.symbol.paperplane'))
              }
              GridItem() {
                this.AccountStatCard('星标邮件', this.starMailCount.toString(), $r('sys.symbol.star'))
              }
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(Constants.GAP_MEDIUM)
            .rowsGap(Constants.GAP_MEDIUM)
            .width('100%')

            Column() {
              this.ActionRow('账号管理', '主邮箱与副邮箱', $r('sys.symbol.person_2'), () => {
                this.isShown = false
                if (this.onManageAccounts) {
                  this.onManageAccounts()
                }
              })
              Divider().color($r('app.color.divider')).margin({ left: 56, right: 16 })
              this.ActionRow('账号设置', '修改密码与删除账户', $r('sys.symbol.gearshape'), () => {
                this.showAccountSettings = true
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
            .border({ width: 1, color: $r('app.color.divider') })

            Button('退出登录', { type: ButtonType.Capsule, stateEffect: true })
              .width('100%')
              .height(48)
              .fontSize(Constants.FONT_SIZE_SUBTITLE)
              .fontColor($r('sys.color.icon_on_primary'))
              .backgroundColor($r('app.color.danger'))
              .onClick(() => {
                this.showLogoutConfirm = true
              })

            Blank().height(24)
          }
          .width('100%')
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: {
          title: { mainTitle: '账号中心' },
          backIcon: {
            label: '返回',
            icon: $r('sys.symbol.chevron_backward'),
            isEnabled: true,
            action: () => { this.isShown = false }
          },
          menu: {
            maxCount: 1,
            value: [{
              content: {
                label: '关闭',
                icon: $r('sys.symbol.xmark'),
                isEnabled: true,
                action: () => { this.isShown = false }
              }
            }]
          }
        },
        style: {
          scrollEffectOpts: { enableScrollEffect: false },
          blurStrategy: BlurStrategy.DISABLE,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent, blurRadius: 0 },
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
        this.isShown = false
        return true
      })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .blur(this.showAccountSettings || this.showLogoutConfirm ? 12 : 0)
      .bindSheet($$this.showAccountSettings, this.AccountSettingsSheet(), {
        height: '84%',
        dragBar: false,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_THICK,
        maskColor: 0x1A000000,
        enableOutsideInteractive: false
      })

      if (this.showLogoutConfirm) {
        this.LogoutConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private AccountStatCard(title: string, value: string, icon: Resource) {
    Column({ space: Constants.GAP_SMALL }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(Constants.SIZE_ICON_SMALL)
          .fontColor([$r('app.color.primary')])
        Text(title)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text(value)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(82)
    .padding(Constants.PADDING_CARD)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private ActionRow(title: string, description: string, icon: Resource, action: () => void) {
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
        Text(description)
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(Constants.SIZE_ICON_SMALL)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(68)
    .padding({ left: 16, right: 16 })
    .onClick(action)
  }

  @Builder
  private AccountSettingsSheet() {
    Stack() {
      HdsNavDestination() {
        Scroll() {
          Column({ space: Constants.GAP_MEDIUM }) {
            this.SectionTitle('账号信息')
            Column() {
              this.ProfileInfoRow('华为账号', this.getHuaweiDisplayName())
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
              this.ProfileInfoRow('主邮箱', this.getPrimaryEmailValue())
            }
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
            .border({ width: 1, color: $r('app.color.divider') })

            this.SectionTitle('安全设置')
            Column() {
              this.ActionRow('修改密码', '设置新的邮箱账户密码', $r('sys.symbol.lock'), () => {
                this.newPassword = ''
                this.confirmPassword = ''
                this.showPasswordDialog = true
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
            .border({ width: 1, color: $r('app.color.divider') })

            this.SectionTitle('危险操作')
            Column({ space: Constants.GAP_MEDIUM }) {
              Column({ space: 6 }) {
                Text('删除账户')
                  .fontSize(Constants.FONT_SIZE_SUBTITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.danger'))
                Text('此操作将永久停用邮箱账户并解除华为账号绑定，无法恢复。')
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Button('删除账户', { type: ButtonType.Capsule, stateEffect: true })
                .width('100%')
                .height(44)
                .fontColor($r('sys.color.icon_on_primary'))
                .backgroundColor($r('app.color.danger'))
                .onClick(() => { this.showDeleteAccountDialog = true })
            }
            .width('100%')
            .padding(Constants.PADDING_EDGE)
            .backgroundColor($r('app.color.card'))
            .borderRadius(Constants.RADIUS_CARD)
            .border({ width: 1, color: $r('app.color.divider') })

            Blank().height(24)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 8, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: {
          title: { mainTitle: '账号设置' },
          backIcon: {
            label: '返回',
            icon: $r('sys.symbol.chevron_backward'),
            isEnabled: true,
            action: () => { this.showAccountSettings = false }
          },
          menu: {
            maxCount: 1,
            value: [{
              content: {
                label: '关闭',
                icon: $r('sys.symbol.xmark'),
                isEnabled: true,
                action: () => { this.showAccountSettings = false }
              }
            }]
          }
        },
        style: {
          scrollEffectOpts: { enableScrollEffect: false },
          blurStrategy: BlurStrategy.DISABLE,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent, blurRadius: 0 },
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
        this.showAccountSettings = false
        return true
      })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))

      if (this.showPasswordDialog) {
        this.ChangePasswordDialog()
      }
      if (this.showDeleteAccountDialog) {
        this.DeleteAccountDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(Constants.FONT_SIZE_SMALL)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 4, top: 4, bottom: 4 })
  }

  @Builder
  private ProfileInfoRow(label: string, value: string) {
    Row({ space: Constants.GAP_MEDIUM }) {
      Text(label)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_secondary'))
        .width(72)
      Text(value)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  private ChangePasswordDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      Column({ space: Constants.GAP_MEDIUM }) {
        Text('修改密码')
          .fontSize(Constants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        TextInput({ text: this.newPassword, placeholder: '输入新密码（至少6位）' })
          .type(InputType.Password)
          .height(48)
          .backgroundColor($r('app.color.background'))
          .borderRadius(Constants.RADIUS_SMALL)
          .onChange((value: string) => { this.newPassword = value })
        TextInput({ text: this.confirmPassword, placeholder: '再次输入新密码' })
          .type(InputType.Password)
          .height(48)
          .backgroundColor($r('app.color.background'))
          .borderRadius(Constants.RADIUS_SMALL)
          .onChange((value: string) => { this.confirmPassword = value })
        Row() {
          Button('取消', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.profileSubmitting)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.background'))
            .onClick(() => { this.showPasswordDialog = false })
          Button(this.profileSubmitting ? '保存中' : '保存', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.profileSubmitting)
            .fontColor($r('sys.color.icon_on_primary'))
            .backgroundColor($r('app.color.primary'))
            .margin({ left: Constants.GAP_MEDIUM })
            .onClick(() => { this.changePassword() })
        }
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

  @Builder
  private DeleteAccountDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      Column({ space: Constants.GAP_MEDIUM }) {
        Text('确认删除账户')
          .fontSize(Constants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('账户、邮箱数据及华为账号绑定将无法恢复。确定继续吗？')
          .fontSize(Constants.FONT_SIZE_COMMON)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Row() {
          Button('取消', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.profileSubmitting)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.background'))
            .onClick(() => { this.showDeleteAccountDialog = false })
          Button(this.profileSubmitting ? '删除中' : '永久删除', { type: ButtonType.Normal, stateEffect: true })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.profileSubmitting)
            .fontColor($r('sys.color.icon_on_primary'))
            .backgroundColor($r('app.color.danger'))
            .margin({ left: Constants.GAP_MEDIUM })
            .onClick(() => { this.deleteAccount() })
        }
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
        Text('退出后需要重新使用华为账号登录才能进入邮箱。')
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
            .onClick(() => {
              this.showLogoutConfirm = false
              this.isShown = false
              if (this.onLogout) {
                this.onLogout()
              }
            })
        }
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

  private async loadHuaweiIdentity(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cachedBinding: HuaweiAccountBinding | null = HuaweiAccountCache.load(context, this.authEmail)
    if (cachedBinding !== null) {
      this.applyHuaweiIdentity(cachedBinding)
      this.identityLoaded = true
    }
    if (!HuaweiAccountCache.shouldRefresh(this.authEmail)) {
      this.identityLoaded = true
      this.notifyIdentityChanged()
      return
    }
    try {
      const binding: HuaweiAccountBinding | null = await HuaweiAccountApi.current()
      this.identityLoaded = true
      if (binding === null) {
        this.notifyIdentityChanged()
        return
      }
      this.applyHuaweiIdentity(binding)
      HuaweiAccountCache.save(context, this.authEmail, binding)
      HuaweiAccountCache.markRefreshed(this.authEmail)
    } catch (err) {
      this.identityLoaded = true
      console.error('load account center identity failed')
    }
    this.notifyIdentityChanged()
  }

  private applyHuaweiIdentity(binding: HuaweiAccountBinding): void {
    this.huaweiNickName = binding.nickName
    this.huaweiAvatarUrl = binding.avatarUrl
    this.huaweiPrimaryEmail = binding.primaryEmail
    this.huaweiUserId = binding.huaweiUserId
    this.userCreateTime = binding.userCreateTime
    this.receiveMailCount = binding.receiveCount
    this.sentMailCount = binding.sentCount
    this.starMailCount = binding.starCount
    this.notifyIdentityChanged()
  }

  private notifyIdentityChanged(): void {
    if (this.onIdentityChanged) {
      this.onIdentityChanged(this.huaweiAvatarUrl, this.getHuaweiAvatarText())
    }
  }

  private getHuaweiDisplayName(): string {
    if (!this.identityLoaded) {
      return '正在读取华为账号'
    }
    if (this.huaweiNickName !== '') {
      return this.huaweiNickName
    }
    return this.huaweiUserId === '' ? '华为账号资料待更新' : '华为账号 · ' + this.huaweiUserId
  }

  private getHuaweiAvatarText(): string {
    const value: string = this.huaweiNickName === '' ? this.authEmail : this.huaweiNickName
    return value === '' ? '华' : value.substring(0, 1).toUpperCase()
  }

  private getPrimaryEmailValue(): string {
    return this.huaweiPrimaryEmail === '' ? this.authEmail : this.huaweiPrimaryEmail
  }

  private getPrimaryEmailLabel(): string {
    const email: string = this.getPrimaryEmailValue()
    return email === '' ? '暂未绑定主邮箱' : '主邮箱：' + email
  }

  private getRegistrationTime(): string {
    return DateTimeUtils.formatUtcDateTime(this.userCreateTime, '暂无')
  }

  private async changePassword(): Promise<void> {
    if (this.newPassword.length < 6) {
      this.showToast('新密码至少需要6位')
      return
    }
    if (this.newPassword !== this.confirmPassword) {
      this.showToast('两次输入的密码不一致')
      return
    }
    this.profileSubmitting = true
    try {
      await ProfileApi.resetPassword(this.newPassword)
      this.showPasswordDialog = false
      this.newPassword = ''
      this.confirmPassword = ''
      this.showToast('密码修改成功')
    } catch (err) {
      this.showToast(err instanceof Error && err.message !== '' ? err.message : '密码修改失败，请重试')
    } finally {
      this.profileSubmitting = false
    }
  }

  private async deleteAccount(): Promise<void> {
    this.profileSubmitting = true
    try {
      await ProfileApi.deleteAccount()
      this.showDeleteAccountDialog = false
      this.showAccountSettings = false
      this.isShown = false
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      HuaweiAccountCache.clear(context, this.authEmail)
      this.showToast('账户已删除')
      if (this.onLogout) {
        this.onLogout()
      }
    } catch (err) {
      this.showToast(err instanceof Error && err.message !== '' ? err.message : '删除账户失败，请重试')
    } finally {
      this.profileSubmitting = false
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
