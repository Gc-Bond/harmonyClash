import { common, Want, bundleManager } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { rpc } from '@kit.IPCKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StartParams, VPN_ABILITY_NAME, VpnCommand, VpnStatus } from './VpnProtocol';

const DOMAIN = 0x0000;
const TAG = 'harmonyClash.client';

// 界面进程这一侧：拉起并连接 VpnExtAbility，发 start / stop / status
export class VpnClient {
  private context: common.UIAbilityContext;
  private remote: rpc.IRemoteObject | undefined;
  private connectionId: number = -1;
  private connecting: Promise<rpc.IRemoteObject> | undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  start(params: StartParams): Promise<VpnStatus> {
    return this.request(VpnCommand.START, JSON.stringify(params));
  }

  stop(): Promise<VpnStatus> {
    return this.request(VpnCommand.STOP, '');
  }

  status(): Promise<VpnStatus> {
    return this.request(VpnCommand.STATUS, '');
  }

  disconnect(): void {
    if (this.connectionId !== -1) {
      this.context.disconnectServiceExtensionAbility(this.connectionId);
    }
    this.reset();
  }

  private reset(): void {
    this.remote = undefined;
    this.connectionId = -1;
    this.connecting = undefined;
  }

  private async request(command: VpnCommand, payload: string): Promise<VpnStatus> {
    const remote = await this.connect();
    const data = rpc.MessageSequence.create();
    const reply = rpc.MessageSequence.create();
    const option = new rpc.MessageOption(rpc.MessageOption.TF_SYNC);
    try {
      data.writeString(payload);
      const result = await remote.sendMessageRequest(command, data, reply, option);
      if (result.errCode !== 0) {
        throw new Error(`IPC 请求失败: errCode=${result.errCode}`);
      }
      return JSON.parse(result.reply.readString()) as VpnStatus;
    } finally {
      data.reclaim();
      reply.reclaim();
    }
  }

  private connect(): Promise<rpc.IRemoteObject> {
    if (this.remote) {
      return Promise.resolve(this.remote);
    }
    if (this.connecting) {
      return this.connecting;
    }
    const want: Want = {
      bundleName: this.context.applicationInfo.name,
      abilityName: VPN_ABILITY_NAME,
    };
    this.connecting = vpnExtension.startVpnExtensionAbility(want).then(() => {
      return new Promise<rpc.IRemoteObject>((resolve, reject) => {
        this.connectionId = this.context.connectServiceExtensionAbility(want, {
          onConnect: (elementName: bundleManager.ElementName, remote: rpc.IRemoteObject) => {
            hilog.info(DOMAIN, TAG, 'connected');
            this.remote = remote;
            resolve(remote);
          },
          onDisconnect: (elementName: bundleManager.ElementName) => {
            hilog.info(DOMAIN, TAG, 'disconnected');
            this.reset();
          },
          onFailed: (code: number) => {
            hilog.error(DOMAIN, TAG, 'connect failed: %{public}d', code);
            this.reset();
            reject(new Error(`连接 VPN 扩展失败: ${code}`));
          },
        });
      });
    });
    this.connecting.catch(() => this.reset());
    return this.connecting;
  }
}
