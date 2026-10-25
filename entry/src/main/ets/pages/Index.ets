import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { GroupList, MihomoApi, MihomoProxy, ProxyList } from '../api/MihomoApi';
import { formatTrafficBytes, TrafficSampler, TrafficSnapshot } from '../api/TrafficStats';
import { Profile, ProfileStore, writeAtomic } from '../profile/ProfileStore';
import { buildRuntimeConfig, RuntimeMode } from '../profile/RuntimeConfig';
import { getOrCreateSecret } from '../profile/SecretStore';
import { VpnClient } from '../vpn/VpnClient';
import { StartParams, VpnStatus } from '../vpn/VpnProtocol';
import { parseProxyCatalog, ProxyCatalogGroup } from '../profile/ProxyCatalog';

const DOMAIN = 0x0000;
const TAG = 'harmonyClash.ui';
const TRAFFIC_INTERVAL_MS = 2000;
// 修改人：gc；修改时间：2026-10-25 21:36:00。
// 修改说明：界面以内容和常用操作为主，所有前景与底色使用语义资源，随系统明暗模式保持对比度。
const TEXT: ResourceColor = $r('app.color.ui_text');
const MUTED: ResourceColor = $r('app.color.ui_muted');
const ACCENT: ResourceColor = $r('app.color.ui_accent');
const ON_ACCENT: ResourceColor = $r('app.color.ui_on_accent');
const BG: ResourceColor = $r('app.color.ui_background');
const SURFACE: ResourceColor = $r('app.color.ui_surface');
const SURFACE_ALT: ResourceColor = $r('app.color.ui_surface_alt');
const LINE: ResourceColor = $r('app.color.ui_line');
const FIELD: ResourceColor = $r('app.color.ui_field');
const ACCENT_SOFT: ResourceColor = $r('app.color.ui_accent_soft');
const POSITIVE: ResourceColor = $r('app.color.ui_positive');
const NEGATIVE: ResourceColor = $r('app.color.ui_negative');

// 统一 24px 矢量视口；路径与线宽一同缩放到 vp，避免高密度真机中图标过小或偏移。
const ICON_POWER = 'M8 5 A8 8 0 1 0 16 5 M12 2 V12';
const ICON_DOWN = 'M12 4 V20 M6 14 L12 20 L18 14';
const ICON_UP = 'M12 20 V4 M6 10 L12 4 L18 10';
const ICON_PROFILE = 'M7 3 H15 L20 8 V21 H4 V3 Z M14 3 V9 H20 M8 13 H16 M8 17 H14';
const ICON_PROXY = 'M4 12 H20 M12 4 V20 M4 8 V16 M20 8 V16 M8 4 H16 M8 20 H16';
const ICON_DASHBOARD = 'M3 3 H10 V10 H3 Z M14 3 H21 V10 H14 Z M3 14 H10 V21 H3 Z M14 14 H21 V21 H14 Z';
const ICON_CHEVRON = 'M9 5 L16 12 L9 19';
const ICON_PLUS = 'M12 4 V20 M4 12 H20';
const ICON_MORE = 'M12 4 V5 M12 11 V12 M12 18 V19';

/**
 * 图标 Builder 的引用参数；调用处直接传对象字面量，让动态颜色由 ArkUI 跟踪，而不是保存首次渲染值。
 * 作者：gc；创建时间：2026-10-25 21:55:22。
 */
interface IconParams {
  path: string;
  color: ResourceColor;
  size: number;
}

class DelayItem {
  name: string = '';
  value: number = 0;
}

@Entry
@Component
struct Index {
  @State private tab: number = 0;
  @State private status: VpnStatus = new VpnStatus();
  // 修改人：gc；修改时间：2026-10-25 21:33:34。
  // 修改说明：运行统计只发布内核聚合值和真实差分；未知累计值/速率均为 -1，不能用零流量替代尚未采样或请求失败。
  @State private traffic: TrafficSnapshot = new TrafficSnapshot();
  @State private mode: RuntimeMode = 'rule';
  // 修改人：gc；修改时间：2026-10-22 17:57:14。
  // 修改说明：当前内核模式与下次连接模式独立保存；连接中的首次订阅导入只安排下次使用规则模式，不伪造内核当前状态。
  @State private nextMode: RuntimeMode = 'rule';
  // VPN 操作单独互斥，耗时测速、订阅下载不能阻止用户断开；运行配置只记录本界面实际启动成功的快照。
  @State private vpnBusy: boolean = false;
  @State private runningProfileKnown: boolean = false;
  @State private runningProfileId: string = '';
  @State private runningProfileName: string = '';
  @State private runningProfileUpdatedAt: number = 0;
  @State private profiles: Profile[] = [];
  @State private activeId: string = '';
  @State private groups: MihomoProxy[] = [];
  // 节点协议取自当前目录来源：运行时使用内核 /proxies，未连接使用本地配置，不从名称猜测协议。
  @State private proxyTypes: Record<string, string> = {};
  // 稳定组名复用网格时，Builder 入参可能仍指向旧组对象；选择态单独整体发布，保证摘要和卡片直接订阅最新内核选择。
  @State private proxySelections: Record<string, string> = {};
  // 修改人：gc；修改时间：2026-10-25 22:49:12；修改说明：离线配置目录与内核运行数据明确区分，预览不伪造选中态或测速结果。
  @State private localProxyCatalog: boolean = true;
  @State private unloadedProviderCount: number = 0;
  @State private proxyCatalogWarnings: Record<string, string> = {};
  @State private expandedGroup: string = '';
  @State private proxySearch: string = '';
  // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：搜索由顶栏显式进入，关键词仅在当前搜索会话内保留。
  @State private proxySearchActive: boolean = false;
  @State private delays: DelayItem[] = [];
  @State private importKind: number = 0;
  @State private profileImportVisible: boolean = false;
  @State private profileName: string = '';
  @State private profileUrl: string = '';
  @State private profileYaml: string = '';
  @State private busy: boolean = false;
  @State private notice: string = '';
  @State private orbPressed: boolean = false;
  // 修改人：gc；修改时间：2026-10-22 14:28:00。
  // 修改说明：代理页使用组内反馈与待切换节点状态，确保长列表里的异步操作在触点附近可见。
  @State private proxyFeedbackGroup: string = '';
  @State private proxyFeedback: string = '';
  @State private proxyFeedbackNode: string = '';
  @State private proxyFeedbackError: boolean = false;
  @State private pendingNode: string = '';
  private client: VpnClient | undefined = undefined;
  private api: MihomoApi | undefined = undefined;
  private store: ProfileStore | undefined = undefined;
  private homeDir: string = '';
  // 每次开始连接或断开时递增；旧会话的查询、测速和切换结果不得恢复已清空的组或覆盖新会话反馈。
  private vpnEpoch: number = 0;
  // 页面可见性与独立监控代数共同约束轮询，页面进入后台或会话切换后，迟到请求不得重新安排定时器。
  private pageVisible: boolean = false;
  private trafficEpoch: number = 0;
  private trafficMonitoring: boolean = false;
  private trafficTimer: number = -1;
  private trafficFailureReported: boolean = false;
  private trafficSampler: TrafficSampler = new TrafficSampler();
  // 修改人：gc；修改时间：2026-10-22 00:27:00。
  // 修改说明：配置页长表单会把资料库推到首屏之外；绑定滚动控制器，让页内跳转有明确且可测试的入口。
  private pageScroller: Scroller = new Scroller();
  // 输入框首次布局后才申请一次焦点；清词和切组不会重新弹出用户已收起的键盘。
  private proxySearchController: TextInputController = new TextInputController();
  private proxySearchNeedsFocus: boolean = false;
  private proxySearchLastGroup: string = '';

  aboutToAppear(): void {
    // 修改人：gc；修改时间：2026-10-25 21:33:34；修改说明：仅可见页面订阅运行统计，初次状态查询确认运行后才启动采样。
    this.pageVisible = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.homeDir = context.filesDir;
    this.client = new VpnClient(context);
    this.store = new ProfileStore(this.homeDir);
    try {
      this.api = new MihomoApi(getOrCreateSecret(this.homeDir));
      this.reloadProfiles();
      // 修改人：gc；修改时间：2026-10-22 00:30:00。
      // 修改说明：无活动配置时启动只会生成直连配置，初始选中态必须与实际运行模式一致。
      if (!this.activeId) {
        this.mode = 'direct';
        this.nextMode = 'direct';
      }
      this.refreshStatus();
    } catch (error) {
      this.showError('初始化失败', error);
    }
  }

  aboutToDisappear(): void {
    // 修改人：gc；修改时间：2026-10-25 21:33:34；修改说明：页面销毁时释放统计定时器并失效所有在途统计响应。
    this.pageVisible = false;
    this.stopTrafficMonitoring();
    this.client?.disconnect();
  }

  /**
   * 页面回到前台时重新确认 VPN 状态，避免以后台前保留的运行状态直接恢复统计。
   * 首次展示可能早于上下文初始化，因此只在客户端与 API 已创建后请求；此回调不等待网络或阻塞界面。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  onPageShow(): void {
    this.pageVisible = true;
    if (this.client && this.api && !this.vpnBusy) {
      this.refreshStatus();
    }
  }

  /**
   * ArkUI 在页面被遮蔽及应用退到后台时调用此生命周期，组件未销毁时也必须暂停轮询。
   * 只清理本地计时器和统计状态，不停止 VPN，不等待在途 HTTP 请求。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  onPageHide(): void {
    this.pageVisible = false;
    this.stopTrafficMonitoring();
  }

  /**
   * 页面收到系统返回时优先退出代理搜索；输入法先处理其自身返回，配置弹层继续使用系统关闭流程。
   * 返回 true 仅表示本页已经退出搜索，不改变当前策略组或内核状态。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  onBackPress(): boolean {
    if (this.profileImportVisible || this.tab !== 1 || !this.proxySearchActive) {
      return false;
    }
    this.endProxySearch();
    return true;
  }

  /**
   * 按原始输入对组成员名做忽略大小写的字面包含匹配，空格和竖线均保留原意，不扩展为正则或协议搜索。
   * 始终从响应式组列表读取成员，避免稳定组名复用 Builder 时保留旧组对象。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private matchedProxyNames(group: MihomoProxy): string[] {
    const current = this.groups.find((item: MihomoProxy) => item.name === group.name);
    const names = current?.all ?? [];
    const keyword = this.proxySearchActive ? this.proxySearch.toLowerCase() : '';
    return keyword.length === 0 ? names : names.filter((name: string) => name.toLowerCase().includes(keyword));
  }

  /**
   * 搜索同时过滤全部策略组；非空词隐藏无成员命中的组，空词沿用原有列表及顺序。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private visibleProxyGroups(): MihomoProxy[] {
    return !this.proxySearchActive || this.proxySearch.length === 0 ? this.groups :
      this.groups.filter((group: MihomoProxy) => this.matchedProxyNames(group).length > 0);
  }

  /**
   * 让浏览组始终属于当前可见结果；零结果清除选中态但记住最后有效组，清词后优先沿用该组。
   * 当前组仍匹配时不跳组；失配时只选择列表中首个匹配组，不改变内核的节点选择。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private reconcileProxyGroup(): void {
    const visible = this.visibleProxyGroups();
    if (visible.length === 0) {
      if (this.expandedGroup) {
        this.proxySearchLastGroup = this.expandedGroup;
      }
      this.expandedGroup = '';
      return;
    }
    if (!visible.some((group: MihomoProxy) => group.name === this.expandedGroup)) {
      const previous = !this.expandedGroup ?
        visible.find((group: MihomoProxy) => group.name === this.proxySearchLastGroup) : undefined;
      this.expandedGroup = previous ? previous.name : visible[0].name;
    }
    this.proxySearchLastGroup = this.expandedGroup;
  }

  /**
   * 接收输入框原值并统一更新跨组结果；不记录关键词日志，也不改写用户输入。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private updateProxySearch(value: string): void {
    this.proxySearch = value;
    this.reconcileProxyGroup();
  }

  /**
   * 只切换可见策略标签并保留搜索词；名称来自页面展示的组，不触发内核操作。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private selectProxyGroup(groupName: string): void {
    if (this.visibleProxyGroups().some((group: MihomoProxy) => group.name === groupName)) {
      this.expandedGroup = groupName;
      this.proxySearchLastGroup = groupName;
    }
  }

  /**
   * 有节点目录的代理页均可进入搜索；焦点交给输入框首次布局回调，避免对尚未挂载的节点申请焦点。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private beginProxySearch(): void {
    // 修改人：gc；修改时间：2026-10-25 22:49:12；修改说明：搜索只操作本地展示数据，不要求 VPN 已连接。
    if (this.tab !== 1 || this.vpnBusy || this.groups.length === 0) {
      return;
    }
    this.proxySearchNeedsFocus = true;
    this.proxySearchActive = true;
    this.reconcileProxyGroup();
    hilog.info(DOMAIN, TAG, '======>>>>>>【代理页进入节点搜索】<<<<<<======');
  }

  /**
   * 输入框布局完成后申请一次焦点并弹出软键盘；后续清词、切组或键盘尺寸变化不重复申请。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private focusProxySearch(): void {
    if (this.proxySearchActive && this.proxySearchNeedsFocus) {
      this.proxySearchNeedsFocus = false;
      this.getUIContext().getFocusController().requestFocus('proxy-search-input');
    }
  }

  /**
   * 清空按钮只恢复全组结果，保持搜索模式和最后有效组，不强制重新取得焦点或弹键盘。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private clearProxySearch(): void {
    this.updateProxySearch('');
  }

  /**
   * 显式返回、离开代理页和会话失效时退出搜索并清词；仅搜索活跃时结束输入，避免干扰配置表单。
   * 退出后沿用最近有效的浏览组，不恢复进入搜索前的旧组，也不改变内核出口。
   * 作者：gc；创建时间：2026-10-25 22:14:00。
   */
  private endProxySearch(): void {
    if (this.proxySearchActive) {
      this.proxySearchController.stopEditing();
      hilog.info(DOMAIN, TAG, '======>>>>>>【代理页退出节点搜索并清空关键词】<<<<<<======');
    }
    this.proxySearchNeedsFocus = false;
    this.proxySearchActive = false;
    this.proxySearch = '';
    this.reconcileProxyGroup();
  }

  /**
   * 格式化字节/秒供速度标签使用；负值或非有限数代表未就绪，返回未知占位而非 0 B/s。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private trafficRateText(value: number): string {
    const text = formatTrafficBytes(value);
    return text === '—' ? text : `${text}/s`;
  }

  /**
   * 格式化累计字节数供流量标签使用；仅格式转换，不在展示层推算或填充缺失数据。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private trafficTotalText(value: number): string {
    return formatTrafficBytes(value);
  }

  /**
   * 检查一次统计请求是否仍属于当前可见页面和当前 VPN 会话；两个代数分别防止后台恢复和重连后的旧响应回写。
   * vpnEpoch 与 trafficEpoch 均为请求发起时的快照，返回 false 时不得发布数据或安排下一次采样。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private isCurrentTrafficSession(vpnEpoch: number, trafficEpoch: number): boolean {
    return this.pageVisible && this.trafficMonitoring && trafficEpoch === this.trafficEpoch &&
      this.isCurrentVpnSession(vpnEpoch);
  }

  /**
   * 在运行状态确认且页面可见时启动独立监控；重复调用不创建第二条轮询链，也不占用业务 busy 或 VPN 连接锁。
   * 首次请求立即发出，后续每次请求完成后再等待两秒，避免内核响应变慢时并发堆积请求。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private startTrafficMonitoring(): void {
    if (!this.pageVisible || !this.isCurrentVpnSession(this.vpnEpoch) || this.trafficMonitoring) {
      return;
    }
    this.trafficMonitoring = true;
    this.trafficFailureReported = false;
    const epoch = ++this.trafficEpoch;
    this.traffic = this.trafficSampler.reset();
    hilog.info(DOMAIN, TAG, '======>>>>>>【开始读取内核聚合统计，不读取连接明细到界面】<<<<<<======');
    this.pollTraffic(this.vpnEpoch, epoch);
  }

  /**
   * 立即停止安排新采样并清空差分基线；HTTP 在途响应通过监控代数丢弃，不等待请求返回，因此不会延迟断开。
   * 页面隐藏、销毁、连接切换及内核状态停止时均调用，重复调用无网络副作用。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private stopTrafficMonitoring(): void {
    const wasMonitoring = this.trafficMonitoring;
    this.trafficMonitoring = false;
    ++this.trafficEpoch;
    if (this.trafficTimer !== -1) {
      clearTimeout(this.trafficTimer);
      this.trafficTimer = -1;
    }
    this.traffic = this.trafficSampler.reset();
    if (wasMonitoring) {
      hilog.info(DOMAIN, TAG, '======>>>>>>【运行统计已暂停，定时器及差分基线已释放】<<<<<<======');
    }
  }

  /**
   * 串行读取聚合统计，使用系统启动后的单调毫秒数计算真实采样间隔，系统时间校准不影响速度。
   * 失败时清除当前可用态和历史，只打印无连接明细的状态日志；恢复后先重建基线，不跨越失败区间伪造瞬时速度。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  private async pollTraffic(vpnEpoch: number, trafficEpoch: number): Promise<void> {
    if (!this.isCurrentTrafficSession(vpnEpoch, trafficEpoch)) {
      return;
    }
    try {
      const totals = await this.api!.getTrafficTotals();
      if (!this.isCurrentTrafficSession(vpnEpoch, trafficEpoch)) {
        return;
      }
      const sampledAt = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false);
      this.traffic = this.trafficSampler.sample(totals, sampledAt);
      if (this.trafficFailureReported) {
        hilog.info(DOMAIN, TAG, '======>>>>>>【内核聚合统计已恢复，重新建立速度基线】<<<<<<======');
        this.trafficFailureReported = false;
      }
    } catch (error) {
      if (!this.isCurrentTrafficSession(vpnEpoch, trafficEpoch)) {
        return;
      }
      // 修改人：gc；修改时间：2026-10-25 21:51:04；修改说明：先构造完整失败快照再整体发布，确保界面能区分统计暂不可用与等待采样。
      const unavailable = this.trafficSampler.reset();
      unavailable.unavailable = true;
      this.traffic = unavailable;
      if (!this.trafficFailureReported) {
        // /connections 错误体可能含目标或规则等连接信息；统计失败不进入通用 notice，也不把错误原文写到日志。
        hilog.warn(DOMAIN, TAG, '======>>>>>>【内核聚合统计暂不可用，速度与累计值显示未知】<<<<<<======');
        this.trafficFailureReported = true;
      }
    } finally {
      if (this.isCurrentTrafficSession(vpnEpoch, trafficEpoch)) {
        this.trafficTimer = setTimeout(() => {
          this.trafficTimer = -1;
          this.pollTraffic(vpnEpoch, trafficEpoch);
        }, TRAFFIC_INTERVAL_MS);
      }
    }
  }

  private showError(action: string, error: Object): void {
    const message = (error as Error).message ?? JSON.stringify(error);
    this.notice = `${action}：${message}`;
    // 下载错误可能含订阅 URL 或令牌，详细内容只在应用内展示，不写入公开系统日志。
    hilog.error(DOMAIN, TAG, '%{private}s', this.notice);
  }

  private reloadProfiles(): void {
    this.profiles = this.store!.list();
    this.activeId = this.store!.active()?.id ?? '';
    // 修改人：gc；修改时间：2026-10-25 22:49:12；修改说明：未连接时随配置选择、导入和更新重建节点目录，运行中仍只展示实际内核会话。
    if (!this.status.running) {
      // 修改人：gc；修改时间：2026-10-25 22:55:09；修改说明：配置来源变化时退出旧搜索，避免旧订阅关键词遮住新配置节点。
      this.endProxySearch();
      this.proxySearchLastGroup = '';
      this.loadLocalProxyGroups();
    }
  }

  /**
   * 从活动配置解析只读目录，不启动内核或隧道；节点、策略组与协议均来自本地 YAML。
   * 无策略组时“全部节点”仅作为浏览聚合；远程 provider 未缓存的节点不虚构，解析问题明确显示。
   * 作者：gc；创建时间：2026-10-25 22:49:12。
   */
  private loadLocalProxyGroups(): void {
    this.localProxyCatalog = true;
    this.groups = [];
    this.proxyTypes = {};
    this.proxySelections = {};
    this.unloadedProviderCount = 0;
    this.proxyCatalogWarnings = {};
    this.delays = [];
    this.proxyFeedbackGroup = '';
    this.proxyFeedback = '';
    this.proxyFeedbackNode = '';
    this.pendingNode = '';
    // 修改人：gc；修改时间：2026-10-25 22:55:09；修改说明：未导入配置是正常空态；活动配置为空或损坏仍交给解析器明确报错。
    if (!this.activeId) {
      this.expandedGroup = '';
      return;
    }
    try {
      const catalog = parseProxyCatalog(this.store!.activeYaml());
      this.unloadedProviderCount = catalog.unloadedProviders.length;
      this.proxyTypes = catalog.proxyTypes;
      const warnings: Record<string, string> = {};
      this.groups = catalog.groups.map((group: ProxyCatalogGroup): MihomoProxy => {
        warnings[group.name] = group.warnings.join('；');
        return { name: group.name, type: group.type, all: group.all };
      });
      if (this.groups.length === 0 && catalog.proxies.length > 0) {
        this.groups = [{ name: '全部节点', type: 'Local', all: catalog.proxies }];
        warnings['全部节点'] = catalog.warnings.join('；');
      }
      this.proxyCatalogWarnings = warnings;
      this.reconcileProxyGroup();
      hilog.info(DOMAIN, TAG, '======>>>>>>【本地节点目录已读取，策略组数=%{public}d，节点数=%{public}d】<<<<<<======',
        this.groups.length, catalog.proxies.length);
    } catch (error) {
      this.expandedGroup = '';
      this.showError('读取本地节点失败', error);
    }
  }

  private activeName(): string {
    return this.profiles.find((item: Profile) => item.id === this.activeId)?.name ?? '暂无配置';
  }

  /**
   * 返回连接卡片应显示的配置名称：运行时只展示本次启动快照，进程重开后不以本地选择猜测内核所用配置。
   * 无连接时返回下次选用名称；无订阅启动的会话明确显示直连。此方法无副作用。
   * 作者：gc；创建时间：2026-10-22 17:57:14。
   */
  private connectionProfileName(): string {
    if (!this.status.running) {
      return this.activeName();
    }
    if (!this.runningProfileKnown) {
      return '运行配置待确认';
    }
    return this.runningProfileId ? this.runningProfileName : '无订阅 · 直连';
  }

  /**
   * 根据运行快照、下次选择和订阅版本生成短提示，保证同一配置更新后也不会被当成已应用。
   * 仅用于展示，不触发重连或更新内核。
   * 作者：gc；创建时间：2026-10-22 17:57:14。
   */
  private connectionProfileHint(): string {
    if (!this.status.running) {
      return '下次连接使用';
    }
    if (!this.runningProfileKnown) {
      return '重连后可确认运行配置';
    }
    if (this.runningProfileId !== this.activeId) {
      return '已选择其他配置，重连后生效';
    }
    const selected = this.profiles.find((item: Profile) => item.id === this.activeId);
    if (selected && selected.updatedAt !== this.runningProfileUpdatedAt) {
      return '订阅已更新，重连后生效';
    }
    if (this.nextMode !== this.mode) {
      return `下次连接使用${this.modeLabel(this.nextMode)}模式`;
    }
    return '正在运行';
  }

  /**
   * 返回资料库单项状态；profile 为列表中的配置。未选且未运行的项不显示标签，未知会话不宣称正在运行。
   * 运行快照的更新时间与本地版本不同，表示修改尚未加载到内核。
   * 作者：gc；创建时间：2026-10-22 17:57:14。
   */
  private profileStateLabel(profile: Profile): string {
    if (this.status.running && this.runningProfileKnown && profile.id === this.runningProfileId) {
      if (profile.updatedAt !== this.runningProfileUpdatedAt) {
        return profile.id === this.activeId ? '更新待重连' : '正在运行旧版';
      }
      return '正在运行';
    }
    return profile.id === this.activeId ? '下次连接使用' : '';
  }

  /**
   * 校验异步请求是否仍属于当前可操作的运行会话，供节点切换、测速及代理组读取统一丢弃过期结果。
   * epoch 为请求发起时的会话代数；返回 false 时调用方不得写回内核数据或过期反馈。
   * 作者：gc；创建时间：2026-10-22 17:57:14。
   */
  private isCurrentVpnSession(epoch: number): boolean {
    return epoch === this.vpnEpoch && this.status.running && !this.vpnBusy;
  }

  private async refreshStatus(): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14。
    // 修改说明：初始化查询可能晚于用户连接返回；会话代数阻止旧状态回写，恢复已有连接时配置身份保持未知。
    const epoch = this.vpnEpoch;
    try {
      const nextStatus = await this.client!.status();
      if (epoch !== this.vpnEpoch || this.vpnBusy) {
        return;
      }
      if (!nextStatus.running || nextStatus.startTime !== this.status.startTime) {
        // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：搜索词只属于当前运行会话，停止或更换会话后立即退出搜索。
        this.endProxySearch();
        this.proxySearchLastGroup = '';
        // 修改人：gc；修改时间：2026-10-25 21:33:34；修改说明：累计计数不能跨内核会话做差分，状态查询发现停止或会话变化时重置监控。
        this.stopTrafficMonitoring();
        this.runningProfileKnown = false;
        this.runningProfileId = '';
        this.runningProfileName = '';
        this.runningProfileUpdatedAt = 0;
      }
      this.status = nextStatus;
      if (this.status.running) {
        this.startTrafficMonitoring();
        const configs = await this.api!.getConfigs();
        if (!this.isCurrentVpnSession(epoch)) {
          return;
        }
        const currentMode = String(configs['mode']);
        if (currentMode === 'rule' || currentMode === 'global' || currentMode === 'direct') {
          const followsRuntime = this.nextMode === this.mode;
          this.mode = currentMode;
          if (followsRuntime) {
            this.nextMode = currentMode;
          }
        }
        await this.loadGroups();
      } else {
        this.loadLocalProxyGroups();
      }
    } catch (error) {
      if (epoch === this.vpnEpoch && !this.vpnBusy) {
        this.showError('查询状态失败', error);
      }
    }
  }

  // 运行配置只在连接时写入；更新订阅或切换活动配置后，用户重新连接即可应用。
  private async startVpn(): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14。
    // 修改说明：启动仍等待配置写入完成；断开不受此限制。连接成功后快照记录实际加载的配置，而非随后选中的资料库项。
    if (this.vpnBusy || this.busy) {
      return;
    }
    this.vpnBusy = true;
    // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：新连接不继承旧会话搜索词或待申请的输入焦点。
    this.endProxySearch();
    this.proxySearchLastGroup = '';
    // 修改人：gc；修改时间：2026-10-25 21:33:34；修改说明：新连接生成独立采样基线，旧会话的请求及定时器立即失效。
    this.stopTrafficMonitoring();
    const epoch = ++this.vpnEpoch;
    this.notice = '';
    this.proxyFeedbackGroup = '';
    this.proxyFeedback = '';
    this.proxyFeedbackNode = '';
    try {
      // 修改人：gc；修改时间：2026-10-25 23:12:41；修改说明：用户已决定移除普通连接通知，连接入口不再请求通知授权。
      const profile = this.store!.active();
      const source = this.store!.activeYaml();
      const secret = getOrCreateSecret(this.homeDir);
      const runtimeMode: RuntimeMode = source ? this.nextMode : 'direct';
      writeAtomic(`${this.homeDir}/config.yaml`, buildRuntimeConfig(source, secret, runtimeMode));
      const params = new StartParams();
      params.homeDir = this.homeDir;
      params.setupParams = JSON.stringify({ 'selected-map': {} as Record<string, string>,
        'test-url': 'https://www.gstatic.com/generate_204' } as Record<string, Object>);
      const nextStatus = await this.client!.start(params);
      // 连接结果到达时才更新状态与文案，避免授权弹窗期间出现虚假的“已连接”状态。
      this.getUIContext().animateTo({ curve: curves.springMotion(0.52, 0.82) }, () => this.status = nextStatus);
      if (nextStatus.error) {
        throw new Error(nextStatus.error);
      }
      if (!nextStatus.running || !nextStatus.tun) {
        throw new Error('内核未确认 VPN 隧道建立');
      }
      this.mode = runtimeMode;
      this.nextMode = runtimeMode;
      this.runningProfileKnown = true;
      this.runningProfileId = profile?.id ?? '';
      this.runningProfileName = profile?.name ?? '';
      this.runningProfileUpdatedAt = profile?.updatedAt ?? 0;
      // 修改人：gc；修改时间：2026-10-25 23:12:41；修改说明：连接状态仅由卡片表达，成功后清空旧提示，不再保留通知错误分支。
      this.notice = '';
      hilog.info(DOMAIN, TAG, '======>>>>>>【VPN 连接成功，存在订阅=%{public}s，模式=%{public}s】<<<<<<======',
        String(this.runningProfileId !== ''), runtimeMode);
    } catch (error) {
      this.runningProfileKnown = false;
      this.runningProfileId = '';
      this.runningProfileName = '';
      this.runningProfileUpdatedAt = 0;
      this.showError('启动失败', error);
    } finally {
      this.vpnBusy = false;
    }
    // 代理组加载属于查询，不延长 VPN 互斥；内核已连接时用户可立即断开，迟到的结果由会话代数丢弃。
    if (this.isCurrentVpnSession(epoch)) {
      this.startTrafficMonitoring();
      try {
        await this.loadGroups();
      } catch (error) {
        if (this.isCurrentVpnSession(epoch)) {
          this.showError('代理组加载失败，可在代理页重试', error);
        }
      }
    }
  }

  private async stopVpn(): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14。
    // 修改说明：仅连接/断开互斥，测速或下载中仍可停止；先失效旧请求，停止确认后再清运行快照。
    if (this.vpnBusy) {
      return;
    }
    this.vpnBusy = true;
    // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：断开开始即退出搜索，不等待内核停止响应或残留键盘。
    this.endProxySearch();
    this.proxySearchLastGroup = '';
    // 修改人：gc；修改时间：2026-10-25 21:33:34；修改说明：停止不等待统计 HTTP；先清理定时器并使在途采样失效，再发送停止命令。
    this.stopTrafficMonitoring();
    ++this.vpnEpoch;
    try {
      const nextStatus = await this.client!.stop();
      this.getUIContext().animateTo({ curve: curves.springMotion(0.52, 0.82) }, () => this.status = nextStatus);
      if (nextStatus.error || nextStatus.running || nextStatus.tun) {
        throw new Error(nextStatus.error || '内核未确认 VPN 已停止');
      }
      this.runningProfileKnown = false;
      this.runningProfileId = '';
      this.runningProfileName = '';
      this.runningProfileUpdatedAt = 0;
      this.groups = [];
      this.proxyTypes = {};
      this.proxySelections = {};
      this.delays = [];
      this.expandedGroup = '';
      this.proxyFeedbackGroup = '';
      this.proxyFeedback = '';
      this.proxyFeedbackNode = '';
      this.pendingNode = '';
      this.mode = this.nextMode;
      // 修改人：gc；修改时间：2026-10-25 22:39:28；修改说明：断开后直接更新卡片，不再显示重复的状态提醒。
      this.notice = '';
      this.loadLocalProxyGroups();
      hilog.info(DOMAIN, TAG, '======>>>>>>【VPN 已断开，运行配置快照及旧会话数据已清除】<<<<<<======');
    } catch (error) {
      this.showError('停止失败', error);
    } finally {
      this.vpnBusy = false;
      // 停止失败且内核仍运行时允许重新采样；成功停止时 startTrafficMonitoring 的运行状态检查会直接返回。
      this.startTrafficMonitoring();
    }
  }

  private async changeMode(nextMode: RuntimeMode): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14。
    // 修改说明：模式写入避开连接切换；用户断开期间返回的内核响应不得再改变当前或待用模式。
    if (this.busy || this.vpnBusy || (this.mode === nextMode && this.nextMode === nextMode)) {
      return;
    }
    // 修改人：gc；修改时间：2026-10-22 00:30:00。
    // 修改说明：没有活动配置时规则和全局模式不会写入运行配置，阻止出现虚假的选中态与生效提示。
    if (!this.activeId && nextMode !== 'direct') {
      this.notice = '请先导入配置，再使用规则或全局模式';
      return;
    }
    this.busy = true;
    const epoch = this.vpnEpoch;
    try {
      if (this.status.running) {
        await this.api!.setMode(nextMode);
        if (!this.isCurrentVpnSession(epoch)) {
          return;
        }
        this.notice = `已切换到${this.modeLabel(nextMode)}模式`;
      } else {
        this.notice = '模式将在下次连接时生效';
      }
      // 模式段落在后端确认成功后再移动视觉选中态，失败时保持原来的状态。
      this.nextMode = nextMode;
      this.getUIContext().animateTo({ curve: curves.springMotion(0.42, 0.86) }, () => this.mode = nextMode);
      hilog.info(DOMAIN, TAG, '======>>>>>>【模式选择已更新，模式=%{public}s，正在运行=%{public}s】<<<<<<======',
        nextMode, String(this.status.running));
    } catch (error) {
      if (epoch === this.vpnEpoch) {
        this.showError('切换模式失败', error);
      }
    } finally {
      this.busy = false;
    }
  }

  private modeLabel(value: RuntimeMode): string {
    return value === 'rule' ? '规则' : value === 'global' ? '全局' : '直连';
  }

  /**
   * 在三个一级页面间切换，同时保留原有表单与展开状态；进入代理页时只对运行中的隧道刷新数据。
   * 输入仅来自底部导航或页面内的明确入口，切换本身不触发 VPN 连接。
   * 作者：gc
   * 创建时间：2026-10-22 00:08:52
   */
  private selectTab(index: number): void {
    if (this.tab === index) {
      return;
    }
    // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：离开代理页即结束搜索，防止其他页面保留隐形输入状态。
    if (this.tab === 1) {
      this.endProxySearch();
    }
    // 修改人：gc；修改时间：2026-10-22 00:29:00。
    // 修改说明：三页共用同一个滚动容器；离开资料库底部时先复位位置，防止新页面从中段显示。
    this.pageScroller.scrollEdge(Edge.Top);
    // 修改人：gc；修改时间：2026-10-22 00:31:00。
    // 修改说明：操作反馈只属于当前页面，切页后清除，避免旧提示挤占新页面的首屏空间。
    this.notice = '';
    this.proxyFeedbackGroup = '';
    this.proxyFeedback = '';
    this.proxyFeedbackNode = '';
    // 页面与导航选中态共用同一次弹性过渡，避免内容先跳转、导航后跟随。
    this.getUIContext().animateTo({ curve: curves.springMotion(0.36, 0.84) }, () => this.tab = index);
    if (index === 1 && !this.vpnBusy) {
      const epoch = this.vpnEpoch;
      this.loadGroups().catch((error: Object) => {
        if (epoch === this.vpnEpoch && !this.vpnBusy) {
          this.showError('刷新代理失败', error);
        }
      });
    }
  }

  private async loadGroups(): Promise<void> {
    if (!this.status.running) {
      // 修改人：gc；修改时间：2026-10-25 22:49:12；修改说明：离线不请求 REST API，直接从活动配置重建可搜索的只读目录。
      this.loadLocalProxyGroups();
      return;
    }
    // 修改人：gc；修改时间：2026-10-25 21:50:56。
    // 修改说明：策略组与节点协议并行读取且共用会话校验；当前选择另存响应式映射，稳定组名复用 Builder 时也能刷新选中态。
    const epoch = this.vpnEpoch;
    const requests: [Promise<GroupList>, Promise<ProxyList>] = [this.api!.getGroups(), this.api!.getProxies()];
    const result = await Promise.all(requests);
    if (!this.isCurrentVpnSession(epoch)) {
      return;
    }
    this.localProxyCatalog = false;
    this.unloadedProviderCount = 0;
    this.proxyCatalogWarnings = {};
    const types: Record<string, string> = {};
    for (const name of Object.keys(result[1].proxies)) {
      types[name] = result[1].proxies[name].type;
    }
    this.proxyTypes = types;
    const selections: Record<string, string> = {};
    for (const group of result[0].proxies) {
      if (group.now !== undefined) {
        selections[group.name] = group.now;
      }
    }
    this.proxySelections = selections;
    // 修改人：gc；修改时间：2026-10-22 14:28:00。
    // 修改说明：优先展示订阅中的手动组，再展示自动组；mihomo 自带的 GLOBAL 放在末尾，避免被误认为订阅生成。
    this.groups = result[0].proxies.filter((item: MihomoProxy) => Array.isArray(item.all))
      .sort((left: MihomoProxy, right: MihomoProxy) => {
        const leftOrder = left.name === 'GLOBAL' ? 2 : left.type === 'Selector' ? 0 : 1;
        const rightOrder = right.name === 'GLOBAL' ? 2 : right.type === 'Selector' ? 0 : 1;
        return leftOrder - rightOrder;
      });
    // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：刷新真实组成员后重算可见组，保留仍有匹配的当前浏览组。
    this.reconcileProxyGroup();
  }

  // 修改人：gc；修改时间：2026-10-22 14:28:00。
  // 修改说明：只允许手动组切换；请求返回后重新读取内核当前选择，再给出成功提示，避免假成功与页首提示不可见。
  private async selectProxy(group: string, name: string): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14；修改说明：节点操作绑定当前 VPN 会话，反馈同时携带节点供列表就地显示。
    if (this.busy || this.vpnBusy || !this.status.running || this.localProxyCatalog) {
      return;
    }
    const current = this.groups.find((item: MihomoProxy) => item.name === group);
    this.proxyFeedbackNode = name;
    if (!current || current.type !== 'Selector' || !current.all?.includes(name)) {
      this.proxyFeedbackGroup = group;
      this.proxyFeedback = '此策略组不支持手动切换该节点';
      this.proxyFeedbackError = true;
      return;
    }
    if (current.now === name) {
      this.proxyFeedbackGroup = group;
      this.proxyFeedback = '已经在使用这个节点';
      this.proxyFeedbackError = false;
      return;
    }
    this.busy = true;
    this.pendingNode = name;
    this.proxyFeedbackGroup = group;
    this.proxyFeedback = '正在切换…';
    this.proxyFeedbackError = false;
    const epoch = this.vpnEpoch;
    try {
      await this.api!.selectProxy(group, name);
      if (!this.isCurrentVpnSession(epoch)) {
        return;
      }
      await this.loadGroups();
      if (!this.isCurrentVpnSession(epoch)) {
        return;
      }
      const updated = this.groups.find((item: MihomoProxy) => item.name === group);
      if (updated?.now !== name) {
        throw new Error('内核未确认节点切换，请稍后重试');
      }
      this.proxyFeedback = this.mode === 'direct'
        ? '已选中；直连模式不经过节点'
        : group === 'GLOBAL' && this.mode !== 'global'
          ? '已选中；全局模式下生效'
          : '节点已切换';
    } catch (error) {
      if (this.isCurrentVpnSession(epoch)) {
        this.showError('切换节点失败', error);
        this.proxyFeedback = this.notice;
        this.proxyFeedbackError = true;
      }
    } finally {
      this.busy = false;
      this.pendingNode = '';
    }
  }

  // 修改人：gc；修改时间：2026-10-22 14:28:00。
  // 修改说明：测速结果写入节点延迟，错误就地回显，用户在长节点列表里无需回到页首寻找结果。
  private async testNode(group: string, name: string): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14；修改说明：断开后忽略迟到测速数据，避免旧节点延迟污染下次会话。
    if (this.busy || this.vpnBusy || !this.status.running || this.localProxyCatalog) {
      return;
    }
    this.busy = true;
    this.proxyFeedbackGroup = group;
    this.proxyFeedbackNode = name;
    // 修改人：gc；修改时间：2026-10-25 23:00:28；修改说明：按钮已表达测速进度，成功直接更新延迟，不再增加进度或完成提示块。
    this.proxyFeedback = '';
    this.proxyFeedbackError = false;
    const epoch = this.vpnEpoch;
    try {
      const delay = await this.api!.testDelay(name);
      if (!this.isCurrentVpnSession(epoch)) {
        return;
      }
      this.setDelay(name, delay);
    } catch (error) {
      if (this.isCurrentVpnSession(epoch)) {
        this.showError('测速失败', error);
        this.proxyFeedback = this.notice;
        this.proxyFeedbackError = true;
      }
    } finally {
      this.busy = false;
    }
  }

  private async testGroup(name: string): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14；修改说明：整组请求复用会话校验，停止不等待 HTTP 请求完成。
    if (this.busy || this.vpnBusy || !this.status.running || this.localProxyCatalog) {
      return;
    }
    this.busy = true;
    this.proxyFeedbackGroup = name;
    this.proxyFeedbackNode = '';
    // 修改人：gc；修改时间：2026-10-25 23:00:28；修改说明：整组测速使用按钮忙碌态和各节点延迟表达结果，仅失败时显示原因。
    this.proxyFeedback = '';
    this.proxyFeedbackError = false;
    const epoch = this.vpnEpoch;
    try {
      const result = await this.api!.testGroupDelay(name);
      if (!this.isCurrentVpnSession(epoch)) {
        return;
      }
      for (const node of Object.keys(result)) {
        this.setDelay(node, result[node]);
      }
    } catch (error) {
      if (this.isCurrentVpnSession(epoch)) {
        this.showError('整组测速失败', error);
        this.proxyFeedback = this.notice;
        this.proxyFeedbackError = true;
      }
    } finally {
      this.busy = false;
    }
  }

  private setDelay(name: string, value: number): void {
    const next = this.delays.filter((item: DelayItem) => item.name !== name);
    const item = new DelayItem();
    item.name = name;
    item.value = value;
    next.push(item);
    this.delays = next;
  }

  private delayText(name: string): string {
    const item = this.delays.find((value: DelayItem) => value.name === name);
    return item ? `${item.value} ms` : '—';
  }

  private async importProfile(): Promise<void> {
    // 修改人：gc；修改时间：2026-10-25 21:41:09。
    // 修改说明：保留首次导入安排下次使用规则模式的行为；导入结果只在该配置确已选中时提示连接生效，避免后续导入被误认为已经替换活动项。
    if (this.busy || this.vpnBusy) {
      return;
    }
    this.busy = true;
    try {
      const hadActiveProfile = this.activeId !== '';
      const item = this.importKind === 0
        ? await this.store!.importUrl(this.profileName, this.profileUrl.trim())
        : this.store!.importText(this.profileName, this.profileYaml);
      this.reloadProfiles();
      if (!hadActiveProfile && this.activeId) {
        this.nextMode = 'rule';
        if (!this.status.running) {
          this.mode = this.nextMode;
        }
        hilog.info(DOMAIN, TAG, '======>>>>>>【首份配置已保存，下次连接使用规则模式，当前会话不变】<<<<<<======');
      }
      this.profileImportVisible = false;
      this.profileName = '';
      this.profileUrl = '';
      this.profileYaml = '';
      // 资料库只自动选中第一份配置；后续导入必须明确提醒用户先选择，不能承诺仅重连就会加载新配置。
      this.notice = item.id === this.activeId
        ? `已导入「${item.name}」${this.status.running ? '，重新连接后生效' : '，连接后生效'}`
        : `已导入「${item.name}」，请点选配置后连接`;
    } catch (error) {
      this.showError('导入配置失败', error);
    } finally {
      this.busy = false;
    }
  }

  private activateProfile(id: string): void {
    // 修改人：gc；修改时间：2026-10-22 17:57:14；修改说明：避免连接读取配置期间切换活动项；本地选择不冒充运行中的配置。
    if (this.busy || this.vpnBusy) {
      return;
    }
    try {
      this.store!.setActive(id);
      this.reloadProfiles();
      this.notice = this.status.running ? '已选择配置，重新连接后生效' : '下次连接使用此配置';
    } catch (error) {
      this.showError('选择配置失败', error);
    }
  }

  private async updateProfile(id: string): Promise<void> {
    // 修改人：gc；修改时间：2026-10-22 17:57:14；修改说明：连接建立期间不修改配置文件，运行版本由启动快照独立表示。
    if (this.busy || this.vpnBusy) {
      return;
    }
    this.busy = true;
    try {
      const item = await this.store!.update(id);
      this.reloadProfiles();
      this.notice = `「${item.name}」已更新${this.status.running && id === this.activeId ? '，重新连接后生效' : ''}`;
    } catch (error) {
      this.showError('更新配置失败', error);
    } finally {
      this.busy = false;
    }
  }

  private trafficText(profile: Profile): string {
    if (profile.total <= 0) {
      return '未提供流量信息';
    }
    const used = (profile.upload + profile.download) / 1024 / 1024 / 1024;
    const total = profile.total / 1024 / 1024 / 1024;
    return `${used.toFixed(1)} / ${total.toFixed(1)} GB`;
  }

  /**
   * 绘制全页统一线性图标；24px 视口与线宽同步缩放，保证真机密度下形状和触控容器相互独立。
   * 作者：gc；创建时间：2026-10-25 21:36:51。
   */
  @Builder
  private icon($$: IconParams) {
    Shape() {
      Path().commands($$.path).fill(Color.Transparent).stroke($$.color)
        .strokeWidth('1.8px').strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
    }.width($$.size).height($$.size)
      .viewPort({ x: '0px', y: '0px', width: '24px', height: '24px' })
  }

  @Builder
  private topBar() {
    // 修改人：gc；修改时间：2026-10-25 22:14:00；修改说明：代理搜索占用顶栏，返回和清空保留独立 44vp 触区，输入仅首次布局时自动取焦点。
    Row({ space: 10 }) {
      if (this.tab === 1 && this.proxySearchActive) {
        Button({ type: ButtonType.Normal }) {
          this.icon({ path: 'M19 12 H5 M12 5 L5 12 L12 19', color: TEXT, size: 24 })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('退出节点搜索').onClick(() => this.endProxySearch())
        TextInput({ placeholder: '搜索节点', text: this.proxySearch, controller: this.proxySearchController })
          .id('proxy-search-input').fontSize(17).fontColor(TEXT).placeholderColor(MUTED)
          .height(44).layoutWeight(1).padding({ left: 0, right: 0 }).backgroundColor(Color.Transparent)
          .enableKeyboardOnFocus(true).accessibilityText('搜索所有策略组节点')
          .onChange((value: string) => this.updateProxySearch(value))
          .onAreaChange(() => this.focusProxySearch())
        Button({ type: ButtonType.Normal }) {
          this.icon({ path: 'M6 6 L18 18 M18 6 L6 18', color: MUTED, size: 24 })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('清空搜索关键词').onClick(() => this.clearProxySearch())
      } else {
        Text(this.tab === 0 ? '仪表盘' : this.tab === 1 ? '代理' : '配置')
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(TEXT)
        Blank()
        if (this.tab === 0) {
          Text('HarmonyClash').fontSize(12).fontColor(MUTED)
        } else if (this.tab === 1) {
          Circle().width(6).height(6).fill(this.status.running ? POSITIVE : MUTED)
          Text(this.status.running ? this.modeLabel(this.mode) + '模式' : '未连接')
            .fontSize(13).fontColor(MUTED)
          Button({ type: ButtonType.Normal }) {
            this.icon({ path: 'M17 17 L21 21 M10.5 3 A7.5 7.5 0 1 0 10.5 18 A7.5 7.5 0 1 0 10.5 3', color: TEXT, size: 24 })
          }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
            .enabled(this.groups.length > 0 && !this.vpnBusy)
            .accessibilityText('搜索节点').onClick(() => this.beginProxySearch())
        } else {
          Text(`${this.profiles.length} 份配置`).fontSize(13).fontColor(MUTED)
          Button({ type: ButtonType.Normal }) {
            this.icon({ path: ICON_PLUS, color: ACCENT, size: 24 })
          }.width(44).height(44).padding(0).borderRadius(14).backgroundColor(ACCENT_SOFT)
            .enabled(!this.busy && !this.vpnBusy).accessibilityText('添加配置')
            .onClick(() => { this.notice = ''; this.profileImportVisible = true; })
        }
      }
    }.width('100%').height(80).padding({ left: 22, right: 20, top: 12, bottom: 8 })
  }

  @Builder
  private noticeBar() {
    if (this.notice) {
      Row({ space: 8 }) {
        Text(this.notice).fontSize(13).fontColor(TEXT).lineHeight(19).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          this.icon({ path: 'M6 6 L18 18 M18 6 L6 18', color: MUTED, size: 18 })
        }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('关闭提示').onClick(() => this.notice = '')
      }.width('100%').padding({ left: 14, right: 2, top: 3, bottom: 3 })
        .backgroundColor(ACCENT_SOFT).borderRadius(12).margin({ bottom: 12 })
    }
  }

  /**
   * 只用两次成功采样之间的实际速率绘制趋势；缺少样本时不制造装饰曲线。
   * 上下行共用真实最大值与时间轴，便于比较；返回 320×52 视口中的折线路径。
   * 作者：gc；创建时间：2026-10-25 21:36:51。
   */
  private trafficPath(upload: boolean): string {
    const samples = this.traffic.history;
    if (samples.length < 2) {
      return '';
    }
    let maxRate = 1;
    samples.forEach((item) => maxRate = Math.max(maxRate, item.uploadRate, item.downloadRate));
    const first = samples[0].sampledAt;
    const span = Math.max(1, samples[samples.length - 1].sampledAt - first);
    return samples.map((item, index: number) => {
      const x = (item.sampledAt - first) / span * 320;
      const y = 32 - (upload ? item.uploadRate : item.downloadRate) / maxRate * 28;
      return `${index === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
    }).join(' ');
  }

  /**
   * 规则模式可能命中多组，首页仅摘要展示首个手动策略的选择，不把它宣称为全部流量的真实出口。
   * 作者：gc；创建时间：2026-10-25 21:36:51。
   */
  private primaryPolicyText(): string {
    if (!this.status.running) {
      return this.activeId ? this.activeName() : '暂无配置';
    }
    if (this.mode === 'direct') {
      return '直连 · 不经过代理节点';
    }
    const group = this.mode === 'global' ? this.groups.find((item: MihomoProxy) => item.name === 'GLOBAL')
      : this.groups.find((item: MihomoProxy) => item.type === 'Selector' && item.name !== 'GLOBAL');
    return group ? `${group.name} · ${group.now ?? '尚未选择'}` : '暂无可用策略组';
  }

  @Builder
  private modeButton(value: RuntimeMode, label: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Stack() {
          Circle().width(18).height(18).fill(Color.Transparent)
            .stroke(this.mode === value ? ACCENT : MUTED).strokeWidth(this.mode === value ? 2 : 1)
          if (this.mode === value) {
            Circle().width(8).height(8).fill(ACCENT)
          }
        }.width(20).height(20)
        Text(label).fontSize(14).fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.mode === value ? ACCENT : TEXT)
        Blank()
      }.width('100%')
    }.width('100%').height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(8)
      .enabled(!this.busy && !this.vpnBusy).accessibilityText(`${label}模式${this.mode === value ? '，已选中' : ''}`)
      .onClick(() => this.changeMode(value))
  }

  @Builder
  private speedMetric(upload: boolean) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        this.icon({ path: upload ? ICON_UP : ICON_DOWN, color: upload ? MUTED : ACCENT, size: 15 })
        Text(upload ? '上传' : '下载').fontSize(12).fontColor(MUTED)
      }
      Text(this.trafficRateText(upload ? this.traffic.uploadRate : this.traffic.downloadRate))
        .fontSize(25).fontWeight(FontWeight.Bold).fontColor(TEXT).maxLines(1)
        .minFontSize(18).maxFontSize(25).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  @Builder
  private overview() {
    // 修改人：gc；修改时间：2026-10-25 21:36:51。
    // 修改说明：首屏以真实流量与常用操作组织信息，移除重复状态、巨大光环与装饰玻璃，停止操作保留独立互斥。
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack() {
          this.icon({ path: ICON_POWER, color: this.status.running ? ACCENT : MUTED, size: 24 })
        }.width(44).height(44).backgroundColor(this.status.running ? ACCENT_SOFT : SURFACE_ALT).borderRadius(14)
        Column({ space: 5 }) {
          Text(this.vpnBusy ? '正在处理连接' : this.status.tun ? 'VPN 已连接' : this.status.running ? '隧道未建立' : 'VPN 未连接')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(TEXT)
          // 修改人：gc；修改时间：2026-10-25 22:40:36；修改说明：正常状态仅保留标题，异常隧道才补充可操作说明。
          if (this.status.running && !this.status.tun) {
            Text('请断开后重新建立连接').fontSize(11).fontColor(MUTED).maxLines(1)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(this.vpnBusy ? '处理中' : this.status.running ? '断开' : '连接', { type: ButtonType.Normal })
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ON_ACCENT)
          .height(44).width(76).borderRadius(14).backgroundColor(ACCENT)
          .enabled(!this.vpnBusy && (this.status.running || !this.busy))
          .scale({ x: this.orbPressed ? 0.95 : 1, y: this.orbPressed ? 0.95 : 1 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down || event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.getUIContext().animateTo({ curve: curves.springMotion(0.25, 0.8) }, () => {
                this.orbPressed = event.type === TouchType.Down;
              });
            }
          }).onClick(() => this.status.running ? this.stopVpn() : this.startVpn())
      }.width('100%').padding(16).backgroundColor(SURFACE).borderRadius(20)

      Column({ space: 14 }) {
        Row() {
          Text('网络速度').fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT)
          Blank()
          if (this.traffic.unavailable) {
            Text('统计暂不可用').fontSize(10).fontColor(MUTED)
          }
        }.width('100%')
        Row({ space: 18 }) {
          this.speedMetric(false)
          this.speedMetric(true)
        }.width('100%')
        // 修改人：gc；修改时间：2026-10-25 22:40:36；修改说明：有真实趋势才占用曲线区域，未连接或等待样本时不显示解释文案和空白图框。
        if (this.traffic.history.length > 1) {
          Stack({ alignContent: Alignment.Center }) {
            // 每条折线分别绑定同一像素视口，避免多个 Path 子节点在真机中使用不同的自然尺寸。
            Shape() {
              Path().commands('M0 3 H320 M0 18 H320 M0 33 H320')
                .fill(Color.Transparent).stroke(LINE).strokeWidth('0.8px')
            }.width('100%').height(36)
              .viewPort({ x: '0px', y: '0px', width: '320px', height: '36px' })
            Shape() {
              Path().commands(this.trafficPath(false)).fill(Color.Transparent).stroke(ACCENT)
                .strokeWidth('2px').strokeLineJoin(LineJoinStyle.Round)
            }.width('100%').height(36)
              .viewPort({ x: '0px', y: '0px', width: '320px', height: '36px' })
            Shape() {
              Path().commands(this.trafficPath(true)).fill(Color.Transparent).stroke(MUTED)
                .strokeWidth('1.5px').strokeLineJoin(LineJoinStyle.Round)
            }.width('100%').height(36)
              .viewPort({ x: '0px', y: '0px', width: '320px', height: '36px' })
          }.width('100%').height(36)
        }
      }.width('100%').padding(16).backgroundColor(SURFACE).borderRadius(20)

      Row({ space: 12 }) {
        Column({ space: 0 }) {
          Text('出站模式').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT)

          this.modeButton('rule', '规则')
          this.modeButton('global', '全局')
          this.modeButton('direct', '直连')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).height(176)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 }).backgroundColor(SURFACE).borderRadius(20)
        Column({ space: 8 }) {
          Text('本次会话').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT)
          Row() {
            Text('下载').fontSize(12).fontColor(MUTED)
            Blank()
            Text(this.trafficTotalText(this.traffic.downloadTotal)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT)
          }.width('100%')
          Row() {
            Text('上传').fontSize(12).fontColor(MUTED)
            Blank()
            Text(this.trafficTotalText(this.traffic.uploadTotal)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT)
          }.width('100%')
          Divider().color(LINE)
          Row() {
            Text('连接数').fontSize(12).fontColor(MUTED)
            Blank()
            Text(this.traffic.ready ? `${this.traffic.connections}` : '—')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ACCENT)
          }.width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).height(176).padding(16)
          .backgroundColor(SURFACE).borderRadius(20)
      }.width('100%').alignItems(VerticalAlign.Top)

      Column() {
        Row({ space: 12 }) {
          this.icon({ path: ICON_PROFILE, color: MUTED, size: 22 })
          Column({ space: 5 }) {
            Text(this.connectionProfileName()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT).maxLines(1)
            Text(this.connectionProfileHint()).fontSize(11).fontColor(MUTED).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          this.icon({ path: ICON_CHEVRON, color: MUTED, size: 16 })
        }.width('100%').padding(14).constraintSize({ minHeight: 64 })
          .onClick(() => this.selectTab(2)).accessibilityText('查看配置')
        Divider().color(LINE).margin({ left: 50, right: 16 })
        Row({ space: 12 }) {
          this.icon({ path: ICON_PROXY, color: MUTED, size: 22 })
          Column({ space: 5 }) {
            Text('代理策略').fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT)
            Text(this.primaryPolicyText()).fontSize(11).fontColor(MUTED).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          this.icon({ path: ICON_CHEVRON, color: MUTED, size: 16 })
        }.width('100%').padding(14).constraintSize({ minHeight: 64 })
          .onClick(() => this.selectTab(1)).accessibilityText('查看代理策略')
      }.width('100%').backgroundColor(SURFACE).borderRadius(20)
    }.width('100%').transition(TransitionEffect.OPACITY)
  }

  @Builder
  private emptyCard(title: string, description: string) {
    Column({ space: 14 }) {
      Stack() {
        this.icon({ path: this.tab === 2 ? ICON_PROFILE : ICON_PROXY, color: ACCENT, size: 30 })
      }.width(64).height(64).borderRadius(22).backgroundColor(ACCENT_SOFT).margin({ bottom: 8 })
      Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(TEXT).textAlign(TextAlign.Center)
      Text(description).fontSize(13).lineHeight(21).fontColor(MUTED).textAlign(TextAlign.Center)
    }.width('100%').padding({ left: 28, right: 28, top: 52, bottom: 24 })
  }

  /**
   * 以横向策略标签组织代理页；搜索在顶栏显式进入，并同步过滤全部组的成员和标签。
   * expandedGroup 只保存当前可见的浏览组，不改变内核选择；零结果不显示不可见组摘要或测速入口。
   * 作者：gc；创建时间：2026-10-25 21:31:50；修改时间：2026-10-25 22:14:00。
   */
  @Builder
  private proxyPage() {
    // 修改人：gc；修改时间：2026-10-25 22:50:58。
    // 修改说明：本地目录与在线目录共用搜索和网格；未连接也可浏览，不再用连接引导遮住已有节点。
    Column({ space: 0 }) {
      if (!this.activeId && this.groups.length === 0) {
        this.emptyCard('暂无配置', '导入配置后即可查看节点。')
        Button('导入配置').fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(ON_ACCENT).backgroundColor(ACCENT)
          .height(48).padding({ left: 24, right: 24 }).borderRadius(24)
          .margin({ top: 20 }).onClick(() => this.selectTab(2))
      } else if (this.groups.length === 0) {
        this.emptyCard(this.localProxyCatalog && this.unloadedProviderCount > 0 ? '节点尚未下载' : '暂无节点',
          this.localProxyCatalog && this.unloadedProviderCount > 0 ? '此配置使用远程节点提供者，连接后可读取节点。' : '请检查当前配置中的节点和策略组。')
      } else if (this.visibleProxyGroups().length === 0) {
        this.emptyCard('未找到匹配节点', '试试其他关键词，或清空搜索查看全部节点。')
      } else {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.visibleProxyGroups(), (group: MihomoProxy) => {
              Button({ type: ButtonType.Normal }) {
                Text(group.name).fontSize(16)
                  .fontWeight(this.expandedGroup === group.name ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.expandedGroup === group.name ? ACCENT : MUTED)
                  .maxLines(1)
              }
              .height(54).padding({ left: 12, right: 12 }).backgroundColor(BG).borderRadius(0)
              .border({ width: { bottom: 3 },
                color: this.expandedGroup === group.name ? ACCENT : BG })
              .onClick(() => this.selectProxyGroup(group.name))
            }, (group: MihomoProxy) => group.name)
          }
        }.width('100%').height(56).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

        // 组名继续使用稳定 key，筛选只切换可见组；节点选择变更不重建同组网格，保持滚动位置。
        ForEach(this.visibleProxyGroups(), (group: MihomoProxy) => {
          if (this.expandedGroup === group.name) {
            this.proxyGroupContent(group)
          }
        }, (group: MihomoProxy) => group.name)
      }
    }.width('100%').height('100%')
  }

  /**
   * 展示当前策略的真实出口、集中测速入口及过滤后的节点网格。
   * 搜索仅过滤展示结果，整组测速仍使用完整组名；自动策略只展示成员，不提供手动选择。
   * 作者：gc；创建时间：2026-10-25 21:31:50。
   */
  @Builder
  private proxyGroupContent(group: MihomoProxy) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.localProxyCatalog) {
          Text(this.activeName()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('本地配置').fontSize(12).fontColor(MUTED)
        } else {
          Column({ space: 4 }) {
            Text(group.type === 'Selector' ? '当前选择' : group.type === 'URLTest' ? '自动选择' : group.type)
              .fontSize(12).fontColor(MUTED)
            Text(this.proxySelections[group.name] || '尚未选择').fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor(TEXT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button(this.busy && this.proxyFeedbackGroup === group.name && !this.proxyFeedbackNode
            ? '测速中…' : '全部测速')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ACCENT)
            .backgroundColor(ACCENT_SOFT).borderRadius(22).height(44)
            .padding({ left: 16, right: 16 }).enabled(!this.busy && !this.vpnBusy && this.status.running)
            .onClick(() => this.testGroup(group.name))
        }
      }.width('100%').padding({ top: 10, bottom: 8 })

      if (this.localProxyCatalog && this.proxyCatalogWarnings[group.name]) {
        Text(this.proxyCatalogWarnings[group.name]).fontSize(12).fontColor(MUTED)
          .width('100%').margin({ bottom: 10 })
      } else if (!this.localProxyCatalog && this.mode === 'direct') {
        Text('直连模式下，流量不经过代理节点').fontSize(12).fontColor(MUTED)
          .width('100%').margin({ bottom: 10 })
      } else if (!this.localProxyCatalog && group.name === 'GLOBAL' && this.mode !== 'global') {
        Text('GLOBAL 仅在全局模式下用于流量出口').fontSize(12).fontColor(MUTED)
          .width('100%').margin({ bottom: 10 })
      } else if (!this.localProxyCatalog && group.type !== 'Selector') {
        Text('此组由内核自动管理，成员不支持手动指定').fontSize(12).fontColor(MUTED)
          .width('100%').margin({ bottom: 10 })
      }

      // 搜索隐藏了刚操作的节点时，将结果保留在网格上方；未过滤时仍紧贴触发节点，避免反馈丢失。
      if (this.proxyFeedbackGroup === group.name && this.proxyFeedback &&
        (!this.proxyFeedbackNode ||
          !this.matchedProxyNames(group).includes(this.proxyFeedbackNode))) {
        this.proxyFeedbackText()
      }
      Row() {
        Text(this.proxySearch.length > 0 ? '搜索结果' : '所有节点').fontSize(12).fontColor(MUTED)
        Blank()
        Text(`${this.matchedProxyNames(group).length} 个节点`)
          .fontSize(12).fontColor(MUTED)
      }.width('100%').padding({ top: 4, bottom: 8 })

      if (this.matchedProxyNames(group).length === 0) {
        this.emptyCard('此组没有节点', '请检查当前配置中的策略组成员。')
        Blank()
      } else {
        Grid() {
          ForEach(this.matchedProxyNames(group), (name: string) => {
            GridItem() {
              this.proxyNodeCard(group, name)
            }
          }, (name: string) => `${group.name}/${name}`)
        }.columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(8)
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
          .padding({ bottom: 12 })
      }
    }.width('100%').layoutWeight(1)
  }

  /**
   * 将节点选择与单节点测速拆成两个独立触区，卡片选中态直接订阅内核选择映射，不依赖复用 Builder 的组对象快照。
   * 手动组顶部可点击选择；自动组顶部保持静态，底部测速按钮仍可操作。
   * 作者：gc；创建时间：2026-10-25 21:31:50。
   */
  @Builder
  private proxyNodeCard(group: MihomoProxy, name: string) {
    // 修改人：gc；修改时间：2026-10-25 21:50:56；修改说明：压缩名称区至 76vp，并直接读取选择映射刷新卡片；节点 key 保持稳定，切换时保留网格滚动位置。
    Column({ space: 0 }) {
      if (!this.localProxyCatalog && group.type === 'Selector') {
        Button({ type: ButtonType.Normal }) {
          this.proxyNodeIdentity(group, name)
        }.width('100%').height(76).padding(0)
          .backgroundColor(this.proxySelections[group.name] === name ? ACCENT_SOFT : SURFACE)
          .borderRadius({ topLeft: 16, topRight: 16 })
          .enabled(!this.busy && !this.vpnBusy && this.status.running)
          .onClick(() => this.selectProxy(group.name, name))
      } else {
        this.proxyNodeIdentity(group, name)
      }
      if (!this.localProxyCatalog) {
        Divider().color(LINE).strokeWidth(0.5)
        Button({ type: ButtonType.Normal }) {
          Row() {
            Text(this.delayText(name)).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor(this.delayText(name) === '—' ? MUTED : TEXT)
            Blank()
            Text(this.busy && this.proxyFeedbackGroup === group.name &&
              this.proxyFeedbackNode === name && !this.pendingNode ? '测速中' : '测速')
              .fontSize(12).fontColor(MUTED)
          }.width('100%')
        }.width('100%').height(44).padding({ left: 12, right: 12 })
          .backgroundColor(this.proxySelections[group.name] === name ? ACCENT_SOFT : SURFACE)
          .borderRadius({ bottomLeft: 16, bottomRight: 16 })
          .accessibilityText(`测试 ${name} 的延迟，当前 ${this.delayText(name)}`)
          .enabled(!this.busy && !this.vpnBusy && this.status.running).onClick(() => this.testNode(group.name, name))
      }
      if (this.proxyFeedbackGroup === group.name && this.proxyFeedbackNode === name && this.proxyFeedback) {
        this.proxyFeedbackText()
      }
    }.width('100%').backgroundColor(this.proxySelections[group.name] === name ? ACCENT_SOFT : SURFACE)
      .borderRadius(16).border({ width: this.proxySelections[group.name] === name ? 1.5 : 1, color: this.proxySelections[group.name] === name ? ACCENT : LINE })
  }

  /**
   * 复用节点名称和真实选中状态的展示，避免手动组与自动组的文字层级分叉。
   * 名称允许两行；等待切换只改变辅助文案，成功后选中勾仍由内核确认结果决定。
   * 作者：gc；创建时间：2026-10-25 21:31:50。
   */
  @Builder
  private proxyNodeIdentity(group: MihomoProxy, name: string) {
    // 修改人：gc；修改时间：2026-10-25 21:46:00；修改说明：次信息展示内核真实协议，取消每卡重复操作提示；使用中和切换中状态与协议并列呈现。
    Column({ space: 6 }) {
      Text(name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(19).width('100%').height(38)
      Row({ space: 4 }) {
        Text(this.proxyTypes[name] ?? '类型待确认').fontSize(11).fontColor(MUTED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (!this.localProxyCatalog && this.status.running && this.proxySelections[group.name] === name) {
          Shape() {
            Path().commands('M 5 12 L 10 17 L 19 7').fill(Color.Transparent)
              .stroke(ACCENT).strokeWidth('2px').strokeLineCap(LineCapStyle.Round)
          }.width(12).height(12).viewPort({ x: '0px', y: '0px', width: '24px', height: '24px' })
        }
        if (this.pendingNode === name && this.proxyFeedbackGroup === group.name) {
          Text('切换中').fontSize(11).fontColor(ACCENT).maxLines(1)
        } else if (!this.localProxyCatalog && this.status.running && this.proxySelections[group.name] === name) {
          Text('使用中').fontSize(11).fontColor(ACCENT).maxLines(1)
        }
      }.width('100%')
    }.width('100%').height(76).alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 9, bottom: 8 })
  }

  /**
   * 使用同一语义色展示节点或整组操作结果；错误同时保留原始中文文案，不只依赖颜色区分。
   * 作者：gc；创建时间：2026-10-25 21:31:50。
   */
  @Builder
  private proxyFeedbackText() {
    Text(this.proxyFeedback).fontSize(12).lineHeight(18)
      .fontColor(this.proxyFeedbackError ? NEGATIVE : TEXT).width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor(SURFACE_ALT).borderRadius(10)
  }

  /**
   * 配置卡的次要操作收纳到原生菜单；主触区负责选择，不再为每条订阅常驻两颗大按钮。
   * 作者：gc；创建时间：2026-10-25 21:38:22。
   */
  private profileMenu(profile: Profile): MenuElement[] {
    const items: MenuElement[] = [{
      value: profile.id === this.activeId ? '已选为连接配置' : '选择此配置',
      enabled: profile.id !== this.activeId && !this.busy && !this.vpnBusy,
      action: () => this.activateProfile(profile.id)
    }];
    if (profile.url) {
      items.push({ value: '更新订阅', enabled: !this.busy && !this.vpnBusy,
        action: () => this.updateProfile(profile.id) });
    }
    return items;
  }

  /**
   * 日期固定以年/月/日展示，避免运行时默认英文区域造成月日顺序歧义；输入时间戳单位为毫秒。
   * 作者：gc；创建时间：2026-10-25 21:43:09。
   */
  private dateLabel(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}/${(date.getMonth() + 1).toString().padStart(2, '0')}/${date.getDate().toString().padStart(2, '0')}`;
  }

  /**
   * 更新时间使用已保存的订阅时间戳，不把浏览、点选时间当成下载成功时间。
   * 作者：gc；创建时间：2026-10-25 21:38:22。
   */
  private profileUpdatedText(profile: Profile): string {
    if (profile.updatedAt <= 0) {
      return '尚无更新时间';
    }
    const time = new Date(profile.updatedAt);
    return `${this.dateLabel(profile.updatedAt)} ${time.getHours().toString().padStart(2, '0')}:${time.getMinutes().toString().padStart(2, '0')} 更新`;
  }

  /**
   * 独立任务面板承载链接和 YAML 导入，列表位置不被表单推走；草稿随页面实例保存。
   * 作者：gc；创建时间：2026-10-25 21:38:22。
   */
  @Builder
  private profileImportForm() {
    Scroll() {
      Column({ space: 22 }) {
        Row({ space: 6 }) {
          Button('订阅链接', { type: ButtonType.Normal })
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.importKind === 0 ? ACCENT : MUTED)
            .backgroundColor(this.importKind === 0 ? SURFACE : Color.Transparent)
            .borderRadius(12).height(44).layoutWeight(1)
            .onClick(() => { this.importKind = 0; this.notice = ''; })
          Button('粘贴 YAML', { type: ButtonType.Normal })
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.importKind === 1 ? ACCENT : MUTED)
            .backgroundColor(this.importKind === 1 ? SURFACE : Color.Transparent)
            .borderRadius(12).height(44).layoutWeight(1)
            .onClick(() => { this.importKind = 1; this.notice = ''; })
        }.width('100%').padding(4).backgroundColor(SURFACE_ALT).borderRadius(16)
          .enabled(!this.busy && !this.vpnBusy)
        Column({ space: 10 }) {
          Text('配置名称').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT)
          TextInput({ placeholder: '例如：我的订阅', text: this.profileName })
            .onChange((value: string) => this.profileName = value)
            .fontSize(15).fontColor(TEXT).placeholderColor(MUTED).backgroundColor(FIELD)
            .borderRadius(12).height(52).enabled(!this.busy)
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.importKind === 0) {
          Column({ space: 10 }) {
            Text('订阅地址').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT)
            TextInput({ placeholder: 'https://…', text: this.profileUrl })
              .onChange((value: string) => this.profileUrl = value)
              .fontSize(15).fontColor(TEXT).placeholderColor(MUTED).backgroundColor(FIELD)
              .borderRadius(12).height(52).enabled(!this.busy)
            Text('支持 Clash / mihomo 格式，导入后可从配置菜单更新。')
              .fontSize(12).lineHeight(19).fontColor(MUTED)
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else {
          Column({ space: 10 }) {
            Text('配置内容').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT)
            TextArea({ placeholder: '粘贴完整的 mihomo YAML 配置', text: this.profileYaml })
              .onChange((value: string) => this.profileYaml = value)
              .fontSize(14).fontColor(TEXT).placeholderColor(MUTED).backgroundColor(FIELD)
              .borderRadius(12).height(220).enabled(!this.busy)
            Text('配置保存在本机应用私有目录。').fontSize(12).fontColor(MUTED)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        if (this.notice) {
          Text(this.notice).fontSize(13).fontColor(NEGATIVE).lineHeight(20).width('100%')
        }
        Button(this.busy ? '正在导入…' : '导入配置', { type: ButtonType.Normal })
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ON_ACCENT).backgroundColor(ACCENT)
          .height(50).width('100%').borderRadius(14)
          .enabled(!this.busy && !this.vpnBusy).onClick(() => this.importProfile())
      }.width('100%').padding({ left: 24, right: 24, top: 12, bottom: 36 })
    }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.TopStart)
  }

  @Builder
  private profilePage() {
    // 修改人：gc；修改时间：2026-10-25 21:38:22。
    // 修改说明：订阅列表成为配置页主体，整卡直接选择；额度、到期和更新时间保持紧凑，导入交给独立 Sheet。
    Column({ space: 12 }) {
      if (this.profiles.length === 0) {
        this.emptyCard('添加第一份配置', '导入订阅链接或粘贴 YAML，开始配置你的代理网络。')
        Button('添加配置', { type: ButtonType.Normal }).fontSize(15).fontColor(ON_ACCENT)
          .backgroundColor(ACCENT).height(48).borderRadius(16)
          .padding({ left: 28, right: 28 }).enabled(!this.busy && !this.vpnBusy)
          .onClick(() => { this.notice = ''; this.profileImportVisible = true; })
      } else {
        Text(this.status.running ? '点选其他配置后，重新连接即可生效' : '点选要在连接时使用的配置')
          .fontSize(12).fontColor(MUTED).width('100%').margin({ top: 2, bottom: 4 })
        ForEach(this.profiles, (profile: Profile) => {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Stack() {
                this.icon({ path: ICON_PROFILE, color: profile.id === this.activeId ? ACCENT : MUTED, size: 22 })
              }.width(40).height(40).borderRadius(12)
                .backgroundColor(profile.id === this.activeId ? ACCENT_SOFT : SURFACE_ALT)
              Column({ space: 5 }) {
                Text(profile.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(TEXT)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(profile.url ? '在线订阅' : '本地配置').fontSize(11).fontColor(MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.profileStateLabel(profile)) {
                Text(this.profileStateLabel(profile)).fontSize(10).fontColor(ACCENT)
                  .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(ACCENT_SOFT).borderRadius(6).maxLines(1)
              }
              Button({ type: ButtonType.Normal }) {
                this.icon({ path: ICON_MORE, color: MUTED, size: 20 })
              }.width(36).height(44).padding(0).backgroundColor(Color.Transparent)
                .enabled(!this.busy && !this.vpnBusy).accessibilityText(`${profile.name}，更多操作`)
                .bindMenu(this.profileMenu(profile))
            }.width('100%')
            if (profile.total > 0) {
              Progress({ value: Math.min(100, (profile.upload + profile.download) / profile.total * 100), total: 100, type: ProgressType.Linear })
                .width('100%').color(ACCENT).backgroundColor(LINE).style({ strokeWidth: 4 })
            }
            Text(`${this.trafficText(profile)}${profile.expire > 0 ? ' · ' + this.dateLabel(profile.expire * 1000) + ' 到期' : ''}`)
              .fontSize(12).fontColor(MUTED).width('100%').maxLines(2).lineHeight(19)
            Text(this.profileUpdatedText(profile)).fontSize(11).fontColor(MUTED).width('100%')
          }.width('100%').padding({ left: 16, right: 10, top: 16, bottom: 16 })
            .backgroundColor(SURFACE).borderRadius(18)
            .border({ width: 1, color: profile.id === this.activeId ? ACCENT : LINE })
            .onClick(() => {
              if (profile.id !== this.activeId && !this.busy && !this.vpnBusy) {
                this.activateProfile(profile.id);
              }
            }).accessibilityText(`${profile.name}，${profile.id === this.activeId ? '已选择' : '点击选择'}`)
        }, (profile: Profile) => `${profile.id}/${profile.updatedAt}`)
      }
    }.width('100%').transition(TransitionEffect.OPACITY)
  }

  @Builder
  private navButton(index: number, title: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Stack() {
          this.icon({ path: index === 0 ? ICON_DASHBOARD : index === 1 ? ICON_PROXY : ICON_PROFILE, color: this.tab === index ? ACCENT : MUTED, size: 22 })
        }.width(62).height(32).borderRadius(16)
          .backgroundColor(this.tab === index ? ACCENT_SOFT : Color.Transparent)
        Text(title).fontSize(11).fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.tab === index ? ACCENT : MUTED)
      }.width('100%').height(58).justifyContent(FlexAlign.Center)
    }.height(62).layoutWeight(1).padding(0).backgroundColor(Color.Transparent).borderRadius(12)
      .accessibilityText(`${title}${this.tab === index ? '，已选中' : ''}`).onClick(() => this.selectTab(index))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor(BG)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      Column() {
        this.topBar()
        if (this.tab === 1) {
          // 节点网格拥有自己的滚动区域，组标签、搜索和测速工具始终留在视口上方。
          Column() {
            this.noticeBar()
            Column() {
              this.proxyPage()
            }.width('100%').layoutWeight(1)
          }.layoutWeight(1).width('100%').padding({ left: 20, right: 20, bottom: 4 })
        } else {
          Scroll(this.pageScroller) {
            Column() {
              this.noticeBar()
              if (this.tab === 0) {
                this.overview()
              } else {
                this.profilePage()
              }
            }.width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
              .padding({ left: 20, right: 20, bottom: 18 })
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.TopStart)
        }
        Row({ space: 10 }) {
          this.navButton(0, '仪表盘')
          this.navButton(1, '代理')
          this.navButton(2, '配置')
        }.width('100%').height(76).padding({ left: 20, right: 20, top: 4, bottom: 10 })
          .border({ width: { top: 1 }, color: LINE }).backgroundColor(BG)
      }.width('100%').height('100%')
    }.width('100%').height('100%').backgroundColor(BG)
      .bindSheet($$this.profileImportVisible, this.profileImportForm(), {
        height: SheetSize.LARGE, title: { title: '添加配置', subtitle: '订阅链接或本地 YAML' },
        backgroundColor: SURFACE, dragBar: true, showClose: true
      })
  }
}
