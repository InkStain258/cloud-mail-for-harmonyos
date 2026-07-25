import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { common, Configuration } from '@kit.AbilityKit'
import { AuthService } from '../common/AuthService'
import { SystemSettingsService } from '../common/SystemSettingsService'
import { AdminService } from '../common/AdminService'
import { DraftService } from '../common/DraftService'
import { PushService } from '../common/PushService'
import { MailService } from '../common/MailService'

const PREF_NAME: string = 'cloud_mail_settings'

let appContext: common.UIAbilityContext | null = null
let mainWindow: window.Window | null = null
const avoidAreaChangeCallback = (data: window.AvoidAreaOptions): void => {
  if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
    updateSafeAreaInsets(data.area)
  }
}

export function setAppContext(ctx: common.UIAbilityContext): void {
  appContext = ctx
}

export default class MailAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    setAppContext(this.context)
    AppStorage.setOrCreate('safeAreaTopPx', 0)
    AppStorage.setOrCreate('safeAreaBottomPx', 0)
    this.applySavedColorMode()
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AuthService.initialize(this.context)
    SystemSettingsService.initialize(this.context)
    DraftService.initialize(this.context)
    AdminService.initialize()
    MailService.initialize()
    PushService.initPush()
    try {
      mainWindow = windowStage.getMainWindowSync()
      mainWindow.setWindowLayoutFullScreen(true)
        .then(() => {
          updateSafeAreaInsets()
        })
        .catch((err: Error) => {
          console.error('set full screen layout failed: ' + JSON.stringify(err))
        })
      mainWindow.on('avoidAreaChange', avoidAreaChangeCallback)
      updateSystemBarForMode(AppStorage.get('currentColorMode') as number)
    } catch (windowErr) {
      console.error('configure immersive window failed: ' + JSON.stringify(windowErr))
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error('loadContent failed: ' + JSON.stringify(err))
        return
      }
    })
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const selectedMode: number | undefined = AppStorage.get('currentColorMode') as number | undefined
    if (selectedMode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET &&
      newConfig.colorMode !== undefined) {
      updateSystemBarForMode(newConfig.colorMode)
    }
  }

  private applySavedColorMode(): void {
    try {
      const dataPref: preferences.Preferences = preferences.getPreferencesSync(
        this.context, { name: PREF_NAME })
      const mode = dataPref.getSync('colorMode', -1) as number
      if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ||
        mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
        this.context.getApplicationContext().setColorMode(mode)
      } else {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      }
      AppStorage.setOrCreate('currentColorMode', mode)
      updateSystemBarForMode(mode)
    } catch (err) {
      try {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      } catch (e) {
        console.error('setColorMode failed')
      }
      AppStorage.setOrCreate('currentColorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    }
  }

  onWindowStageDestroy(): void {
    if (mainWindow !== null) {
      try {
        mainWindow.off('avoidAreaChange', avoidAreaChangeCallback)
      } catch (err) {
        console.error('remove avoid area listener failed: ' + JSON.stringify(err))
      }
    }
    mainWindow = null
  }
  onForeground(): void {}
  onBackground(): void {}
  onDestroy(): void {}
}

export function setAppColorMode(mode: number): void {
  if (appContext === null) {
    return
  }
  try {
    const dataPref: preferences.Preferences = preferences.getPreferencesSync(
      appContext, { name: PREF_NAME })
    dataPref.putSync('colorMode', mode)
    dataPref.flushSync()
    AppStorage.set('currentColorMode', mode)
    appContext.getApplicationContext().setColorMode(mode)
    updateSystemBarForMode(mode)
  } catch (err) {
    console.error('setAppColorMode failed: ' + JSON.stringify(err))
  }
}

function updateSystemBarForMode(mode: number): void {
  if (mainWindow === null) {
    return
  }
  let effectiveMode: number = mode
  if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET && appContext !== null &&
    appContext.config.colorMode !== undefined) {
    effectiveMode = appContext.config.colorMode
  }
  const isDark: boolean = effectiveMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  mainWindow.setWindowSystemBarProperties({
    // 状态栏保持显示但背景透明，由页面顶部不透明背景连续绘制到状态栏区域。
    statusBarColor: '#00000000',
    statusBarContentColor: isDark ? '#E8E8E8' : '#1A1A1A'
  }).catch((err: Error) => {
    console.error('update system bar failed: ' + JSON.stringify(err))
  })
}

function updateSafeAreaInsets(avoidArea?: window.AvoidArea): void {
  if (mainWindow === null && avoidArea === undefined) {
    return
  }
  try {
    const systemArea: window.AvoidArea = avoidArea !== undefined
      ? avoidArea
      : mainWindow!.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    AppStorage.set('safeAreaTopPx', systemArea.topRect.height)
    AppStorage.set('safeAreaBottomPx', systemArea.bottomRect.height)
  } catch (err) {
    console.error('update safe area failed: ' + JSON.stringify(err))
  }
}
