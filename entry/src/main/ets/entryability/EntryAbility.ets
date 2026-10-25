import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const UI_LOG_TAG = 'harmonyClash.ui';

/**
 * 主界面生命周期入口；统一系统栏与页面资源主题，系统切换明暗时保持两者一致。
 * 修改人：gc；修改时间：2026-10-25 21:32:06。
 * 修改说明：移除固定深蓝系统栏，改用当前配置匹配的语义色；不影响代理及 VPN 生命周期。
 */
export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 页面和资源都跟随系统明暗，不在界面入口强制指定某一种主题。
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主界面创建，主题跟随系统】<<<<<<======');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主界面销毁】<<<<<<======');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 窗口建立后才能设置系统栏，先应用语义色，避免页面首帧沿用旧版深蓝背景。
    this.mainWindow = windowStage.getMainWindowSync();
    this.applySystemBarTheme();
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主窗口创建，开始加载首页】<<<<<<======');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, UI_LOG_TAG, '======>>>>>>【首页加载失败，原因=%{public}s】<<<<<<======',
          JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【首页加载完成】<<<<<<======');
    });
  }

  onWindowStageDestroy(): void {
    // 清除已销毁窗口，避免后台配置变化继续向无效的窗口对象发送系统栏更新。
    this.mainWindow = undefined;
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主窗口销毁，释放主题更新目标】<<<<<<======');
  }

  onForeground(): void {
    // 系统可能在应用后台时调整主题；回到前台时从资源管理器重新取得当前颜色。
    this.applySystemBarTheme();
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主界面进入前台】<<<<<<======');
  }

  onBackground(): void {
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【主界面进入后台】<<<<<<======');
  }

  /**
   * 接收系统环境配置变化；资源管理器自动匹配新配置后，同步更新状态栏和导航栏。
   * newConfig 仅用于记录此次系统主题，颜色始终从页面共用的资源读取，避免维护两套色值。
   * 作者：gc；创建时间：2026-10-25 21:32:06。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    this.applySystemBarTheme();
    hilog.info(DOMAIN, UI_LOG_TAG, '======>>>>>>【系统配置变化，触发系统栏主题同步，colorMode=%{public}s】<<<<<<======',
      String(newConfig.colorMode));
  }

  /**
   * 将资源管理器返回的 ARGB 数字转为系统栏接口接受的十六进制颜色字符串。
   * resourceName 必须是已有颜色资源名；读取失败直接交由调用方记录，不替换为隐藏故障的默认色。
   * 作者：gc；创建时间：2026-10-25 21:32:06。
   */
  private resolveSystemBarColor(resourceName: string): string {
    const color = this.context.resourceManager.getColorByNameSync(resourceName);
    return `#${(color >>> 0).toString(16).padStart(8, '0')}`;
  }

  /**
   * 仅在主窗口有效时应用当前主题；背景与文字复用页面语义色，深浅模式由资源系统解析。
   * 配置变化可能先于窗口创建或晚于窗口销毁，因此无窗口时无需执行系统栏调用。
   * 作者：gc；创建时间：2026-10-25 21:32:06。
   */
  private applySystemBarTheme(): void {
    const mainWindow = this.mainWindow;
    if (!mainWindow) {
      return;
    }
    try {
      const backgroundColor = this.resolveSystemBarColor('ui_background');
      const contentColor = this.resolveSystemBarColor('ui_text');
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: backgroundColor,
        statusBarContentColor: contentColor,
        navigationBarColor: backgroundColor,
        navigationBarContentColor: contentColor,
      }).catch((error: Error) => {
        hilog.error(DOMAIN, UI_LOG_TAG, '======>>>>>>【系统栏主题设置失败，原因=%{public}s】<<<<<<======',
          error.message);
      });
    } catch (error) {
      hilog.error(DOMAIN, UI_LOG_TAG, '======>>>>>>【系统栏主题同步失败，原因=%{public}s】<<<<<<======',
        String(error));
    }
  }
}
