import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit'
import { common } from '@kit.AbilityKit'
import { authentication } from '@kit.AccountKit'
import { util } from '@kit.ArkTS'
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit'
import { PromptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SettingsApi, WebsiteConfig } from '../api/SettingsApi'
import Constants from '../common/Constants'
import { AuthResult, AuthService, HuaweiAuthResult } from '../common/AuthService'

enum LoginStage {
  EMAIL_LOGIN,
  HUAWEI_LOGIN,
  CHOOSE_ACTION,
  BIND_EXISTING,
  REGISTER_NEW
}

enum HuaweiLoginErrorCode {
  LOGIN_OUT = 1001502001,
  NETWORK_ERROR = 1001502005,
  INTERNAL_ERROR = 1001502009,
  USER_CANCEL = 1001502012,
  SYSTEM_SERVICE = 12300001,
  REQUEST_REFUSE = 1001500002,
  AGREEMENT_NOT_ACCEPTED = 1005300001,
  INVALID_CLIENT_OR_PROFILE = 1001502003
}

@Component
export struct AuthPage {
  @State stage: LoginStage = LoginStage.EMAIL_LOGIN
  @State agreementAccepted: boolean = false
  @State email: string = ''
  @State password: string = ''
  @State registerCode: string = ''
  @State bindToken: string = ''
  @State registrationCodeRequired: boolean = true
  @State minEmailPrefix: number = 1
  @State isSubmitting: boolean = false
  @StorageLink('registrationEnabled') registrationEnabled: boolean = true
  private toast: PromptAction = this.getUIContext().getPromptAction()
  private huaweiAccountSubscriber: commonEventManager.CommonEventSubscriber | null = null
  private isAccountEventSubscriptionActive: boolean = false
  onAuthenticated?: () => void

  private huaweiLoginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton((error: BusinessError,
        response: loginComponentManager.HuaweiIDCredential) => {
        if (error) {
          this.handleHuaweiLoginError(error)
          return
        }
        if (response && response.authorizationCode) {
          this.loginWithHuaweiProfile(response.authorizationCode)
        }
      })

  aboutToAppear(): void {
    this.isAccountEventSubscriptionActive = true
    this.subscribeHuaweiAccountEvents()
    this.refreshWebsiteConfig()
  }

  aboutToDisappear(): void {
    this.isAccountEventSubscriptionActive = false
    this.unsubscribeHuaweiAccountEvents()
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[$r('app.color.auth_gradient_start'), 0.0], [$r('app.color.auth_gradient_end'), 1.0]]
        })

      if (this.stage === LoginStage.HUAWEI_LOGIN) {
        this.HuaweiLoginPage()
      } else {
        Scroll() {
          Column() {
            this.BrandHeader()
            if (this.stage === LoginStage.EMAIL_LOGIN) {
              this.EmailLoginCard()
            } else if (this.stage === LoginStage.CHOOSE_ACTION) {
              this.ActionChoiceCard()
            } else if (this.stage === LoginStage.BIND_EXISTING) {
              this.BindExistingCard()
            } else {
              this.RegisterCard()
            }
            Blank().height(32)
          }
          .width('100%')
          .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 56, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }

      if (this.isSubmitting) {
        Stack() {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.primary'))
            Text('正在安全登录')
              .fontSize(Constants.FONT_SIZE_COMMON)
              .fontColor($r('app.color.text_primary'))
          }
          .padding(24)
          .backgroundColor($r('app.color.card'))
          .borderRadius(Constants.RADIUS_CARD)
          .shadow(Constants.SHADOW_FLOAT)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private BrandHeader() {
    Column() {
      Stack() {
        Circle()
          .width(72)
          .height(72)
          .foregroundColor($r('app.color.primary'))
        SymbolGlyph($r('sys.symbol.envelope_fill'))
          .fontSize(34)
          .fontColor([$r('sys.color.icon_on_primary')])
      }
      .width(72)
      .height(72)
      .margin({ bottom: 20 })

      Text('云笺集')
        .fontSize(Constants.FONT_SIZE_HERO)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text(this.getStageDescription())
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ bottom: 32 })
  }

  @Builder
  private HuaweiLoginPage() {
    Column() {
      Blank()

      Stack() {
        Circle()
          .width(64)
          .height(64)
          .foregroundColor($r('app.color.primary'))
        SymbolGlyph($r('sys.symbol.envelope_fill'))
          .fontSize(30)
          .fontColor([$r('sys.color.icon_on_primary')])
      }
      .width(64)
      .height(64)

      Text('云笺集')
        .fontSize(Constants.FONT_SIZE_HERO)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })

      Text('一个华为账号，连接你的主邮箱')
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Blank()

      LoginWithHuaweiIDButton({
        params: {
          style: loginComponentManager.Style.BUTTON_RED,
          extraStyle: {
            buttonStyle: new loginComponentManager.ButtonStyle().loadingStyle({ show: true })
          },
          borderRadius: 24,
          loginType: loginComponentManager.LoginType.ID,
          supportDarkMode: true
        },
        controller: this.huaweiLoginController
      })
        .width('100%')
        .height(48)

      Button('切换华为账号', { type: ButtonType.Capsule, stateEffect: true })
        .width('100%')
        .height(48)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_link'))
        .backgroundColor($r('app.color.card'))
        .border({ width: 1, color: $r('app.color.divider') })
        .margin({ top: 12 })
        .enabled(!this.isSubmitting)
        .onClick(() => {
          this.showHuaweiAccountSwitchGuide()
        })

      Row() {
        Checkbox({ name: 'loginAgreement', group: 'loginAgreementGroup' })
          .select(this.agreementAccepted)
          .onChange((accepted: boolean) => {
            this.agreementAccepted = accepted
            this.huaweiLoginController.setAgreementStatus(accepted ?
            loginComponentManager.AgreementStatus.ACCEPTED :
            loginComponentManager.AgreementStatus.NOT_ACCEPTED)
          })
        Text('我已阅读并同意')
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
        Text('《隐私政策》')
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_link'))
          .onClick(() => { this.openPrivacyPolicy() })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 18, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE, top: 40, bottom: 28 })
  }

  @Builder
  private EmailLoginCard() {
    Column({ space: Constants.GAP_MEDIUM }) {
      Text('登录主邮箱')
        .fontSize(Constants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      this.EmailInput()

      TextInput({ placeholder: '邮箱密码', text: this.password })
        .type(InputType.Password)
        .showPasswordIcon(true)
        .height(48)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .border({ width: 0.5, color: $r('app.color.divider') })
        .borderRadius(Constants.RADIUS_SMALL)
        .padding({ left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
        .onChange((value: string) => { this.password = value })

      this.PrimaryActionButton('登录', () => { this.loginWithEmail() })

      Button('没有主邮箱？点我注册', { type: ButtonType.Normal, stateEffect: true })
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_link'))
        .backgroundColor(Color.Transparent)
        .enabled(this.registrationEnabled)
        .onClick(() => {
          this.password = ''
          this.stage = LoginStage.REGISTER_NEW
        })

      if (!this.registrationEnabled) {
        Text('当前站点未开放新邮箱注册。')
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .shadow(Constants.SHADOW_CARD)
  }

  @Builder
  private ActionChoiceCard() {
    Column({ space: Constants.GAP_MEDIUM }) {
      Text('设置你的主邮箱')
        .fontSize(Constants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Button('已经有主邮箱了？点我绑定', { type: ButtonType.Capsule, stateEffect: true })
        .width('100%')
        .height(48)
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontColor($r('sys.color.icon_on_primary'))
        .backgroundColor($r('app.color.primary'))
        .onClick(() => { this.stage = LoginStage.BIND_EXISTING })

      Button('还没有主邮箱，点我注册', { type: ButtonType.Capsule, stateEffect: true })
        .width('100%')
        .height(48)
        .fontSize(Constants.FONT_SIZE_SUBTITLE)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.background'))
        .border({ width: 1, color: $r('app.color.divider') })
        .enabled(this.registrationEnabled)
        .onClick(() => { this.stage = LoginStage.REGISTER_NEW })

      Button('切换华为账号', { type: ButtonType.Normal, stateEffect: true })
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_link'))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.resetHuaweiLoginForAccountSwitch()
          this.showHuaweiAccountSwitchGuide()
        })

      if (!this.registrationEnabled) {
        Text('当前站点未开放新邮箱注册，你仍可以绑定已有主邮箱。')
          .fontSize(Constants.FONT_SIZE_SMALL)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .shadow(Constants.SHADOW_CARD)
  }

  @Builder
  private BindExistingCard() {
    Column({ space: Constants.GAP_MEDIUM }) {
      Text('绑定已有主邮箱')
        .fontSize(Constants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      this.EmailInput()

      TextInput({ placeholder: '原邮箱密码（仅用于本次验证）', text: this.password })
        .type(InputType.Password)
        .showPasswordIcon(true)
        .height(48)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .border({ width: 0.5, color: $r('app.color.divider') })
        .borderRadius(Constants.RADIUS_SMALL)
        .padding({ left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
        .onChange((value: string) => { this.password = value })

      this.PrimaryActionButton('确认绑定', () => { this.bindExisting() })
      this.BackButton()
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .shadow(Constants.SHADOW_CARD)
  }

  @Builder
  private RegisterCard() {
    Column({ space: Constants.GAP_MEDIUM }) {
      Text('注册新的主邮箱')
        .fontSize(Constants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      this.EmailInput()

      TextInput({ placeholder: '设置登录密码（至少 6 位）', text: this.password })
        .type(InputType.Password)
        .showPasswordIcon(true)
        .height(48)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .border({ width: 0.5, color: $r('app.color.divider') })
        .borderRadius(Constants.RADIUS_SMALL)
        .padding({ left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
        .onChange((value: string) => { this.password = value })

      if (this.registrationCodeRequired) {
        TextInput({ placeholder: '注册码', text: this.registerCode })
          .height(48)
          .fontSize(Constants.FONT_SIZE_COMMON)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.background'))
          .border({ width: 0.5, color: $r('app.color.divider') })
          .borderRadius(Constants.RADIUS_SMALL)
          .padding({ left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
          .onChange((value: string) => { this.registerCode = value })
      }

      Text('注册后使用「邮箱 + 密码」登录，密码至少 6 位。')
        .fontSize(Constants.FONT_SIZE_SMALL)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      this.PrimaryActionButton('注册', () => { this.registerNewMailbox() })
      this.BackButton()
    }
    .width('100%')
    .padding(Constants.PADDING_EDGE)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Constants.RADIUS_CARD)
    .shadow(Constants.SHADOW_CARD)
  }

  @Builder
  private EmailInput() {
    Row() {
      TextInput({ placeholder: '主邮箱账号', text: this.email })
        .layoutWeight(1)
        .height(48)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.background'))
        .border({ width: 0.5, color: $r('app.color.divider') })
        .borderRadius(Constants.RADIUS_SMALL)
        .padding({ left: Constants.PADDING_INNER, right: Constants.PADDING_INNER })
        .onChange((value: string) => { this.email = value })
      Text(Constants.MAIL_DOMAIN)
        .fontSize(Constants.FONT_SIZE_COMMON)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height(48)
  }

  @Builder
  private PrimaryActionButton(label: string, action: () => void) {
    Button(label, { type: ButtonType.Capsule, stateEffect: true })
      .width('100%')
      .height(48)
      .fontSize(Constants.FONT_SIZE_SUBTITLE)
      .fontColor($r('sys.color.icon_on_primary'))
      .backgroundColor($r('app.color.primary'))
      .enabled(!this.isSubmitting)
      .onClick(action)
  }

  @Builder
  private BackButton() {
    Button('返回选择', { type: ButtonType.Normal, stateEffect: true })
      .fontSize(Constants.FONT_SIZE_COMMON)
      .fontColor($r('app.color.text_link'))
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.password = ''
        this.registerCode = ''
        this.stage = LoginStage.EMAIL_LOGIN
      })
  }

  private async loginWithHuawei(authorizationCode: string): Promise<void> {
    if (this.isSubmitting) {
      return
    }
    this.isSubmitting = true
    const result: HuaweiAuthResult = await AuthService.loginWithHuawei(authorizationCode)
    this.isSubmitting = false
    if (!result.success) {
      this.showToast(result.message)
      return
    }
    if (result.bound) {
      this.finishAuthentication()
      return
    }
    this.bindToken = result.bindToken
    this.stage = LoginStage.CHOOSE_ACTION
  }

  private loginWithHuaweiProfile(fallbackAuthorizationCode: string): void {
    const request: authentication.AuthorizationWithHuaweiIDRequest =
      new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest()
    request.scopes = ['openid', 'profile']
    request.permissions = ['serviceauthcode']
    request.forceAuthorization = true
    request.state = util.generateRandomUUID()
    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController(this.getUIContext().getHostContext())
    controller.executeRequest(request, (error: BusinessError<Record<string, Object>>,
      data: authentication.AuthenticationResponse) => {
      if (error) {
        this.loginWithHuawei(fallbackAuthorizationCode)
        return
      }
      const response: authentication.AuthorizationWithHuaweiIDResponse =
        data as authentication.AuthorizationWithHuaweiIDResponse
      if (response.state && response.state !== request.state) {
        hilog.error(0x0000, 'CloudMailAuth', 'Huawei profile authorization state mismatch')
        this.loginWithHuawei(fallbackAuthorizationCode)
        return
      }
      const credential: authentication.AuthorizationWithHuaweiIDCredential | undefined = response.data
      if (credential && credential.authorizationCode) {
        this.loginWithHuawei(credential.authorizationCode)
        return
      }
      this.loginWithHuawei(fallbackAuthorizationCode)
    })
  }

  private showHuaweiAccountSwitchGuide(): void {
    this.toast.showDialog({
      title: '切换华为账号',
      message: '云笺集使用设备当前登录的华为账号。\n\n请前往“设置 > 华为账号中心”，退出当前账号并登录另一个账号；返回云笺集后，再点击“华为账号登录”。',
      buttons: [{
        text: '我知道了',
        color: $r('app.color.primary'),
        primary: true
      }]
    }).catch((error: BusinessError) => {
      hilog.error(0x0000, 'CloudMailAuth',
        `Show Huawei account switch guide failed, code=${error.code}, message=${error.message}`)
    })
  }

  private resetHuaweiLoginForAccountSwitch(): void {
    this.bindToken = ''
    this.email = ''
    this.password = ''
    this.registerCode = ''
    this.stage = LoginStage.HUAWEI_LOGIN
  }

  private subscribeHuaweiAccountEvents(): void {
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [
        commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGIN,
        commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGOUT
      ]
    }
    commonEventManager.createSubscriber(subscribeInfo)
      .then((subscriber: commonEventManager.CommonEventSubscriber) => {
        if (!this.isAccountEventSubscriptionActive) {
          return
        }
        this.huaweiAccountSubscriber = subscriber
        commonEventManager.subscribe(subscriber,
          (error: BusinessError, data: commonEventManager.CommonEventData) => {
            if (error) {
              hilog.error(0x0000, 'CloudMailAuth',
                `Subscribe Huawei account event failed, code=${error.code}, message=${error.message}`)
              return
            }
            this.resetHuaweiLoginForAccountSwitch()
            if (data.event === commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGIN) {
              this.showToast('检测到华为账号已登录，请重新登录云笺集')
              return
            }
            if (data.event === commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGOUT) {
              this.showToast('检测到华为账号已退出，请在系统设置中登录其他账号')
            }
          })
      })
      .catch((error: BusinessError) => {
        hilog.error(0x0000, 'CloudMailAuth',
          `Create Huawei account subscriber failed, code=${error.code}, message=${error.message}`)
      })
  }

  private unsubscribeHuaweiAccountEvents(): void {
    const subscriber: commonEventManager.CommonEventSubscriber | null = this.huaweiAccountSubscriber
    if (subscriber === null) {
      return
    }
    this.huaweiAccountSubscriber = null
    commonEventManager.unsubscribe(subscriber, (error: BusinessError) => {
      if (error) {
        hilog.error(0x0000, 'CloudMailAuth',
          `Unsubscribe Huawei account event failed, code=${error.code}, message=${error.message}`)
      }
    })
  }

  private async loginWithEmail(): Promise<void> {
    if (this.isSubmitting) {
      return
    }
    if (!this.validateEmail()) {
      return
    }
    if (this.password === '') {
      this.showToast('请输入邮箱密码')
      return
    }
    this.isSubmitting = true
    const result: AuthResult = await AuthService.login(this.getFullEmail(), this.password)
    this.isSubmitting = false
    if (!result.success) {
      this.showToast(result.message)
      return
    }
    this.finishAuthentication()
  }

  private async bindExisting(): Promise<void> {
    if (!this.validateEmail()) {
      return
    }
    if (this.password === '') {
      this.showToast('请输入原邮箱密码')
      return
    }
    this.isSubmitting = true
    const result: AuthResult =
      await AuthService.bindHuaweiAccount(this.bindToken, this.getFullEmail(), this.password)
    this.isSubmitting = false
    if (!result.success) {
      this.showToast(result.message)
      return
    }
    this.finishAuthentication()
  }

  private async registerNewMailbox(): Promise<void> {
    if (!this.registrationEnabled) {
      this.showToast('当前未开放注册')
      return
    }
    if (!this.validateEmail()) {
      return
    }
    if (this.email.trim().length < this.minEmailPrefix) {
      this.showToast('邮箱账号至少需要 ' + this.minEmailPrefix.toString() + ' 位')
      return
    }
    if (this.registrationCodeRequired && this.registerCode.trim() === '') {
      this.showToast('请输入注册码')
      return
    }
    if (this.password.length < 6) {
      this.showToast('密码至少需要 6 位')
      return
    }
    this.isSubmitting = true
    const result: AuthResult =
      await AuthService.register(this.getFullEmail(), this.password, this.registerCode.trim())
    this.isSubmitting = false
    if (!result.success) {
      this.showToast(result.message)
      return
    }
    this.finishAuthentication()
  }

  private finishAuthentication(): void {
    this.password = ''
    this.registerCode = ''
    this.bindToken = ''
    if (this.onAuthenticated) {
      this.onAuthenticated()
    }
  }

  private validateEmail(): boolean {
    const value: string = this.email.trim()
    if (value === '' || value.indexOf('@') >= 0 || value.indexOf(' ') >= 0) {
      this.showToast('请输入正确的邮箱账号')
      return false
    }
    return true
  }

  private getFullEmail(): string {
    return this.email.trim() + Constants.MAIL_DOMAIN
  }

  private getStageDescription(): string {
    if (this.stage === LoginStage.EMAIL_LOGIN) {
      return '使用邮箱账号登录'
    }
    if (this.stage === LoginStage.HUAWEI_LOGIN) {
      return '使用华为账号安全登录'
    }
    if (this.stage === LoginStage.CHOOSE_ACTION) {
      return '一个华为账号绑定一个主邮箱'
    }
    if (this.stage === LoginStage.BIND_EXISTING) {
      return '验证并绑定你的主邮箱'
    }
    return '创建并绑定新的主邮箱'
  }

  private handleHuaweiLoginError(error: BusinessError): void {
    hilog.error(0x0000, 'CloudMailAuth',
      `Huawei login failed, code=${error.code}, message=${error.message}`)
    if (error.code === HuaweiLoginErrorCode.USER_CANCEL ||
      error.code === HuaweiLoginErrorCode.REQUEST_REFUSE) {
      return
    }
    if (error.code === HuaweiLoginErrorCode.AGREEMENT_NOT_ACCEPTED) {
      this.showToast('请先阅读并同意隐私政策')
      return
    }
    if (error.code === HuaweiLoginErrorCode.NETWORK_ERROR) {
      this.showToast('网络连接失败，请检查网络后重试')
      return
    }
    if (error.code === HuaweiLoginErrorCode.LOGIN_OUT) {
      this.showToast('请先在设备上登录华为账号')
      return
    }
    if (error.code === HuaweiLoginErrorCode.INVALID_CLIENT_OR_PROFILE) {
      this.showToast('华为账号配置校验失败，请更新应用后重试')
      return
    }
    if (error.code === HuaweiLoginErrorCode.SYSTEM_SERVICE ||
      error.code === HuaweiLoginErrorCode.INTERNAL_ERROR) {
      this.showToast('华为账号服务暂时不可用，请稍后重试')
      return
    }
    this.showToast('华为账号登录失败，请重试')
  }

  private async refreshWebsiteConfig(): Promise<void> {
    try {
      const config: WebsiteConfig = await SettingsApi.getWebsiteConfig()
      AppStorage.set('siteTitle', config.title)
      AppStorage.set('registrationEnabled', config.registrationEnabled)
      this.registrationCodeRequired = config.registrationCodeRequired
      this.minEmailPrefix = config.minEmailPrefix
    } catch (err) {
      console.error('load website config failed')
    }
  }

  private async openPrivacyPolicy(): Promise<void> {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      await context.openLink(Constants.PRIVACY_POLICY_URL)
    } catch (err) {
      this.showToast('暂时无法打开隐私政策')
    }
  }

  private showToast(message: string): void {
    try {
      this.toast.openToast({ message: message, duration: 2000 })
    } catch (err) {
      console.error('openToast failed')
    }
  }
}
