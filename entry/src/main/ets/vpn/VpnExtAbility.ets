import { vpnExtension, VpnExtensionAbility, connection } from '@kit.NetworkKit';
import { AbilityConstant, Want, bundleManager } from '@kit.AbilityKit';
import { rpc } from '@kit.IPCKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { forceGC, quickSetup, startTUN, stopTun, suspend, updateDns } from 'core';
import { StartParams, VPN_DESCRIPTOR, VpnCommand, VpnOptions, VpnStatus } from './VpnProtocol';
import NetworkManager from './NetworkManager';
import PowerManager from './PowerManager';

const DOMAIN = 0x0000;
const TAG = 'harmonyClash.vpn';

// 以下地址和参考项目 FlClash-ohos 保持一致
const IPV4_ADDRESS = '172.19.0.1/30';
const IPV6_ADDRESS = 'fdfe:dcba:9876::1/126';
const DNS = '172.19.0.2';
const DNS6 = 'fdfe:dcba:9876::2';
const NET_ANY = '0.0.0.0';
const NET_ANY6 = '::';

class VpnServiceStub extends rpc.RemoteObject {
  private parent: VpnExtAbility;

  constructor(parent: VpnExtAbility) {
    super(VPN_DESCRIPTOR);
    this.parent = parent;
  }

  async onRemoteMessageRequest(code: number, data: rpc.MessageSequence, reply: rpc.MessageSequence,
    option: rpc.MessageOption): Promise<boolean> {
    let status: VpnStatus;
    if (code === VpnCommand.START) {
      status = await this.parent.start(JSON.parse(data.readString()) as StartParams);
    } else if (code === VpnCommand.STOP) {
      status = await this.parent.stop();
    } else if (code === VpnCommand.STATUS) {
      status = this.parent.status;
    } else {
      return false;
    }
    reply.writeString(JSON.stringify(status));
    return true;
  }
}

export default class VpnExtAbility extends VpnExtensionAbility {
  private stub: VpnServiceStub | undefined;
  private vpnConnection: vpnExtension.VpnConnection | undefined;
  private networkManager: NetworkManager | undefined;
  private powerManager: PowerManager | undefined;
  private uidBundleNameMap: Map<number, string> = new Map<number, string>();
  private resolveFailuresLogged: number = 0;
  // 修改人：gc；修改时间：2026-10-25 22:36:19。
  // 修改说明：所有启动和底层销毁共用串行队列；代数在入口立即更新，停止无需等待队列即可失效在途启动。
  private lifecycleQueue: Promise<void> = Promise.resolve();
  private lifecycleEpoch: number = 0;
  private destroyed: boolean = false;
  // 资源标记在 SDK create 返回后立即设置，只有 destroy 成功才清除；销毁失败不能假装资源已释放。
  private vpnCreated: boolean = false;
  private coreReady: boolean = false;
  status: VpnStatus = new VpnStatus();

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    // 修改人：gc；修改时间：2026-10-25 22:36:19；修改说明：生命周期回调保持同步，在途启动立即失效，异步清理失败单独记录。
    this.destroyed = true;
    this.stop().catch((error: Error) => {
      hilog.error(DOMAIN, TAG, '======>>>>>>【扩展销毁清理失败，原因=%{public}s】<<<<<<======', error.message);
    });
  }

  onConnect(want: Want): rpc.RemoteObject {
    if (!this.stub) {
      this.stub = new VpnServiceStub(this);
    }
    return this.stub;
  }

  onDisconnect(want: Want): void {
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
      forceGC();
    }
  }

  /**
   * 新启动先失效旧请求并进入生命周期队列；清理旧 VPN 完成后才允许下一次 quickSetup/create。
   * 异步返回前始终检查本次启动是否仍有效；连接状态由 IPC 返回，不依赖系统通知。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  start(params: StartParams): Promise<VpnStatus> {
    const epoch = ++this.lifecycleEpoch;
    // 修改人：gc；修改时间：2026-10-25 23:12:41；修改说明：用户取消普通连接通知，启动仅维护 VPN 会话代数与资源队列。
    return this.enqueueLifecycle(() => this.startSession(params, epoch));
  }

  /**
   * 立即结束当前流量和输入状态，再串行等待底层销毁；不延误 TUN 关闭。
   * 返回值只在清理完成后提供；销毁失败保留真实资源标记及错误，下一次启动必须再次清理。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  stop(): Promise<VpnStatus> {
    const epoch = ++this.lifecycleEpoch;
    // 修改人：gc；修改时间：2026-10-25 23:12:41；修改说明：停止仅清理内核和系统 VPN 资源，不再撤销已移除的通知实现。
    this.stopActiveTun();
    this.status = new VpnStatus();
    hilog.info(DOMAIN, TAG, '======>>>>>>【VPN 已停止转发，正在串行清理系统资源】<<<<<<======');
    return this.enqueueLifecycle(async (): Promise<VpnStatus> => {
      try {
        await this.releaseVpnResources();
      } catch (error) {
        return this.lifecycleFailure(epoch, '停止 VPN 失败', error);
      }
      return this.status;
    });
  }

  /**
   * 为每次启停保留原始结果，同时让队列屏障在失败后仍能继续；错误仍由原调用者接收，不静默改成成功。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private enqueueLifecycle(operation: () => Promise<VpnStatus>): Promise<VpnStatus> {
    const result = this.lifecycleQueue.then(operation);
    this.lifecycleQueue = result.then((): void => {}, (): void => {});
    return result;
  }

  /**
   * 检查排队或异步返回的启动是否仍属于最新会话；扩展销毁后不允许任何新启动恢复隧道。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private isCurrentStart(epoch: number): boolean {
    return epoch === this.lifecycleEpoch && !this.destroyed;
  }

  /**
   * 同步停止内核转发及监听，系统 VPN 的异步销毁由队列单独等待；重复调用不会重复移除监听。
   * coreReady 覆盖 quickSetup 已完成但 create 尚未返回的阶段，防止停止时只看共享状态而遗漏启动中资源。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private stopActiveTun(): void {
    if (this.coreReady || this.vpnCreated || this.status.running) {
      stopTun();
    }
    this.coreReady = false;
    this.networkManager?.unsubscribe();
    this.networkManager = undefined;
    this.powerManager?.unsubscribe();
    this.powerManager = undefined;
  }

  /**
   * 仅在生命周期队列内等待系统资源销毁；迟到的 create 也必须经过这里，后续启动不能越过该屏障。
   * destroy 拒绝时保持 vpnCreated，向调用者传播错误，避免新 create 与尚存在的系统 VPN 交错。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private async releaseVpnResources(): Promise<void> {
    this.stopActiveTun();
    if (this.vpnCreated) {
      await this.vpnConnection!.destroy();
      this.vpnCreated = false;
      hilog.info(DOMAIN, TAG, '======>>>>>>【系统 VPN 资源已销毁，可开始下一次连接】<<<<<<======');
    }
  }

  /**
   * 记录底层启停失败；只有当前代数可发布错误，旧会话不能覆盖停止状态或下一次连接。
   * 资源尚未销毁时 tun 保留为 true，避免把未完成的系统清理报告为彻底断开。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private lifecycleFailure(epoch: number, label: string, error: Object): VpnStatus {
    const message = `${label}: ${JSON.stringify(error)}`;
    hilog.error(DOMAIN, TAG, '======>>>>>>【VPN 生命周期操作失败，原因=%{public}s】<<<<<<======', message);
    if (epoch === this.lifecycleEpoch) {
      const failed = new VpnStatus();
      failed.tun = this.vpnCreated;
      failed.error = message;
      this.status = failed;
    }
    return this.status;
  }

  /**
   * 执行一个已入队的启动；所有异步边界之后先核对代数，迟到的已创建 VPN 先销毁再释放队列。
   * 本方法独占底层创建/销毁，只有 stop 的同步转发关闭可以在等待期间介入。
   * 作者：gc；创建时间：2026-10-25 22:36:19。
   */
  private async startSession(params: StartParams, epoch: number): Promise<VpnStatus> {
    if (!this.isCurrentStart(epoch)) {
      return this.status;
    }
    try {
      await this.releaseVpnResources();
    } catch (error) {
      return this.lifecycleFailure(epoch, '清理旧 VPN 失败', error);
    }
    if (!this.isCurrentStart(epoch)) {
      return this.status;
    }
    // 修改人：gc；修改时间：2026-10-25 22:38:11；修改说明：旧资源已释放，启动等待阶段不得继续向 STATUS 报告上次连接仍在运行。
    this.status = new VpnStatus();
    const status = new VpnStatus();
    try {
      const error = await this.setupCore(params);
      this.coreReady = error === '';
      if (!this.isCurrentStart(epoch)) {
        await this.releaseVpnResources();
        return this.status;
      }
      if (error !== '') {
        status.error = `内核启动失败: ${error}`;
        this.status = status;
        hilog.error(DOMAIN, TAG, '%{public}s', status.error);
        return status;
      }
      const options = params.options;
      const fd = await this.vpnConnection!.create(this.toVpnConfig(options));
      this.vpnCreated = true;
      if (!this.isCurrentStart(epoch)) {
        await this.releaseVpnResources();
        return this.status;
      }
      startTUN(
        (socketFd: number): Promise<void> => this.vpnConnection!.protect(socketFd).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'protect failed: %{public}s', err.message);
        }),
        (protocol: number, source: string, target: string, uid: number) =>
          this.resolveProcess(protocol, source, target, uid),
        fd,
        options.stack,
        this.toTunAddress(options),
        this.toTunDns(options),
      );
      status.running = true;
      status.tun = true;
      this.networkManager = new NetworkManager();
      this.networkManager.subscribe(updateDns);
      this.powerManager = new PowerManager();
      this.powerManager.subscribe(suspend);
      status.startTime = Date.now();
      this.status = status;
    } catch (error) {
      try {
        await this.releaseVpnResources();
      } catch (cleanupError) {
        return this.lifecycleFailure(epoch, '启动失败且系统 VPN 清理失败', cleanupError);
      }
      return this.lifecycleFailure(epoch, '启动 VPN 失败', error);
    }
    // 修改人：gc；修改时间：2026-10-25 23:12:41；修改说明：TUN 建立后直接返回真实状态，不再发布用户不需要的普通通知。
    hilog.info(DOMAIN, TAG, 'start -> %{public}s', JSON.stringify(this.status));
    return this.status;
  }

  private setupCore(params: StartParams): Promise<string> {
    const initParams: Record<string, string | number> = {
      'home-dir': params.homeDir,
      'version': deviceInfo.sdkApiVersion,
    };
    return new Promise<string>((resolve) => {
      quickSetup((data: string) => resolve(data), JSON.stringify(initParams), params.setupParams);
    });
  }

  private toLinkAddress(cidr: string, family: number): vpnExtension.LinkAddress {
    const parts = cidr.split('/');
    const address: connection.NetAddress = { address: parts[0], family: family };
    return { address: address, prefixLength: Number(parts[1]) };
  }

  private toRouteInfo(cidr: string, family: number): vpnExtension.RouteInfo {
    const destination = this.toLinkAddress(cidr, family);
    const gateway: connection.NetAddress = { address: '', family: family };
    return {
      interface: '',
      destination: destination,
      gateway: gateway,
      hasGateway: false,
      isDefaultRoute: destination.prefixLength === 0,
    };
  }

  private toVpnConfig(options: VpnOptions): vpnExtension.VpnConfig {
    const addresses: vpnExtension.LinkAddress[] = [this.toLinkAddress(IPV4_ADDRESS, 1)];
    const routes: vpnExtension.RouteInfo[] = [this.toRouteInfo(`${NET_ANY}/0`, 1)];
    const dnsAddresses: string[] = [DNS];
    if (options.ipv6) {
      addresses.push(this.toLinkAddress(IPV6_ADDRESS, 2));
      routes.push(this.toRouteInfo(`${NET_ANY6}/0`, 2));
      dnsAddresses.push(DNS6);
    }
    const config: vpnExtension.VpnConfig = {
      addresses: addresses,
      routes: routes,
      dnsAddresses: dnsAddresses,
      mtu: 9000,
      isIPv4Accepted: true,
      isIPv6Accepted: options.ipv6,
      isBlocking: !options.allowBypass,
    };
    return config;
  }

  private toTunAddress(options: VpnOptions): string {
    return options.ipv6 ? `${IPV4_ADDRESS},${IPV6_ADDRESS}` : IPV4_ADDRESS;
  }

  private toTunDns(options: VpnOptions): string {
    if (options.dnsHijacking) {
      return NET_ANY;
    }
    return options.ipv6 ? `${DNS},${DNS6}` : DNS;
  }

  private toNetAddress(addr: string): connection.NetAddress {
    const separator = addr.lastIndexOf(':');
    const host = addr.slice(0, separator);
    const port = Number(addr.slice(separator + 1));
    const address = host.startsWith('[') && host.endsWith(']') ? host.slice(1, -1) : host;
    const family = address.includes(':') ? 2 : 1;
    return { address: address, family: family, port: port };
  }

  // 内核按连接查询发起方应用，返回包名；查不到返回空串
  private resolveProcess(protocol: number, source: string, target: string, uid: number): string {
    let ownerUid = uid;
    try {
      ownerUid = connection.getConnectOwnerUidSync(protocol, this.toNetAddress(source), this.toNetAddress(target));
    } catch (err) {
      this.logResolveFailure(`查询连接 UID 失败: ${JSON.stringify(err)}`);
      return '';
    }
    if (ownerUid === -1) {
      this.logResolveFailure('系统未找到连接 UID');
      return '';
    }
    if (!this.uidBundleNameMap.has(ownerUid)) {
      try {
        this.uidBundleNameMap.set(ownerUid, bundleManager.getBundleNameByUidSync(ownerUid));
      } catch (err) {
        this.logResolveFailure(`UID ${ownerUid} 查询包名失败: ${JSON.stringify(err)}`);
        this.uidBundleNameMap.set(ownerUid, '');
      }
    }
    return this.uidBundleNameMap.get(ownerUid) ?? '';
  }

  private logResolveFailure(message: string): void {
    if (this.resolveFailuresLogged < 5) {
      hilog.warn(DOMAIN, TAG, '%{public}s', message);
      this.resolveFailuresLogged++;
    }
  }
}
