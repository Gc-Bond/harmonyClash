import { MihomoTrafficTotals } from './MihomoApi';

const HISTORY_LIMIT = 30;
const BYTES_PER_UNIT = 1024;
const MILLISECONDS_PER_SECOND = 1000;

/**
 * 一次真实差分产生的速度样本；sampledAt 是单调时钟的毫秒数，速率单位为字节/秒，不是固定轮询间隔的估算。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
export class TrafficPoint {
  sampledAt: number = 0;
  uploadRate: number = 0;
  downloadRate: number = 0;
}

/**
 * 供首页统一读取的统计快照；ready 表示累计值和连接数有效，speedReady 表示已有两次连续有效采样。
 * 未就绪数值使用 -1，界面必须显示未知占位；history 只保存真实速率，不预填零点或复制历史值。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
export class TrafficSnapshot {
  ready: boolean = false;
  speedReady: boolean = false;
  // 修改人：gc；修改时间：2026-10-25 21:51:04；修改说明：区分等待首个样本与请求失败，成功或停止后的新快照默认清除此错误态。
  unavailable: boolean = false;
  uploadRate: number = -1;
  downloadRate: number = -1;
  uploadTotal: number = -1;
  downloadTotal: number = -1;
  connections: number = -1;
  history: TrafficPoint[] = [];
}

/**
 * 按连续内核累计值和单调时间计算真实速度，独立于 UI 与网络请求，便于验证不等间隔、计数回退和恢复场景。
 * 网络错误、会话切换或页面隐藏时必须 reset，防止跨越未知区间生成看似实时的速度。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
export class TrafficSampler {
  private previous: MihomoTrafficTotals | undefined = undefined;
  private previousAt: number = 0;
  private history: TrafficPoint[] = [];

  /**
   * 清除差分基线及历史，返回全部未知的快照；此方法不产生任何流量样本。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  reset(): TrafficSnapshot {
    this.previous = undefined;
    this.previousAt = 0;
    this.history = [];
    return new TrafficSnapshot();
  }

  /**
   * 接收 API 已验证的累计值以及采样完成时的单调毫秒数，返回独立快照。
   * 只有时间前进且两个累计计数均未回退时才计算差分；内核计数重置时保留本次累计值作为新基线，不伪造零速率。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  sample(totals: MihomoTrafficTotals, sampledAt: number): TrafficSnapshot {
    const snapshot = new TrafficSnapshot();
    snapshot.ready = true;
    snapshot.uploadTotal = totals.uploadTotal;
    snapshot.downloadTotal = totals.downloadTotal;
    snapshot.connections = totals.connections;
    const previous = this.previous;
    const elapsed = sampledAt - this.previousAt;
    if (previous && elapsed > 0 && totals.uploadTotal >= previous.uploadTotal &&
      totals.downloadTotal >= previous.downloadTotal) {
      snapshot.speedReady = true;
      snapshot.uploadRate = (totals.uploadTotal - previous.uploadTotal) * MILLISECONDS_PER_SECOND / elapsed;
      snapshot.downloadRate = (totals.downloadTotal - previous.downloadTotal) * MILLISECONDS_PER_SECOND / elapsed;
      const point = new TrafficPoint();
      point.sampledAt = sampledAt;
      point.uploadRate = snapshot.uploadRate;
      point.downloadRate = snapshot.downloadRate;
      this.history = [...this.history, point].slice(-HISTORY_LIMIT);
    } else {
      // 首次、时钟未前进和累计计数重置均没有可比较的连续区间，旧折线不能跨区间连接。
      this.history = [];
    }
    this.previous = totals;
    this.previousAt = sampledAt;
    snapshot.history = this.history;
    return snapshot;
  }
}

/**
 * 将非负字节数格式化为 B、KB、MB、GB、TB；负值或非有限数返回未知占位，真实零才显示 0 B。
 * 此函数只负责展示，不补值或更改原始采样。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
export function formatTrafficBytes(value: number): string {
  if (!Number.isFinite(value) || value < 0) {
    return '—';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let amount = value;
  let unit = 0;
  while (amount >= BYTES_PER_UNIT && unit < units.length - 1) {
    amount /= BYTES_PER_UNIT;
    unit++;
  }
  return `${amount.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}
