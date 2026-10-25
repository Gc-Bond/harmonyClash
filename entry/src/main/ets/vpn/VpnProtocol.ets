// 界面进程和 VpnExtAbility 进程之间的 IPC 约定：只有 start / stop / status 三条命令，
// 参数和返回值都是 JSON 字符串，其余操作走 mihomo REST API。

export const VPN_ABILITY_NAME = 'VpnExtAbility';
export const VPN_DESCRIPTOR = 'harmonyClash.VpnService';

export enum VpnCommand {
  START = 1,
  STOP = 2,
  STATUS = 3,
}

export class VpnOptions {
  // TUN 协议栈：system / gvisor / mixed
  stack: string = 'mixed';
  ipv6: boolean = false;
  // 允许应用绕过 VPN（isBlocking 取反）
  allowBypass: boolean = true;
  // true：劫持所有 53 端口 DNS；false：只接管发往 TUN 内 DNS 地址的请求
  dnsHijacking: boolean = true;
}

export class StartParams {
  // 内核的 home-dir，内核从这里读 config.yaml
  homeDir: string = '';
  // 透传给 quickSetup 的 setupParams（JSON）
  setupParams: string = '{}';
  options: VpnOptions = new VpnOptions();
}

export class VpnStatus {
  // 内核已 quickSetup 成功
  running: boolean = false;
  // TUN 已建立
  tun: boolean = false;
  // 开始运行的时间戳（毫秒），未运行为 0
  startTime: number = 0;
  // 最近一次失败原因，成功为空串
  error: string = '';
}
