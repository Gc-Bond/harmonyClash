import { http } from '@kit.NetworkKit';

const BASE_URL = 'http://127.0.0.1:9090';
const TEST_URL = 'https://www.gstatic.com/generate_204';

export interface MihomoVersion {
  meta: boolean;
  version: string;
}

export interface MihomoProxy {
  name: string;
  type: string;
  now?: string;
  all?: string[];
}

export interface ProxyList {
  proxies: Record<string, MihomoProxy>;
}

export interface GroupList {
  proxies: MihomoProxy[];
}

/**
 * 提供界面运行统计所需的聚合数据，流量单位为字节；禁止把连接目标、应用或规则等明细传到界面状态。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
export interface MihomoTrafficTotals {
  uploadTotal: number;
  downloadTotal: number;
  connections: number;
}

/**
 * 仅在 API 层解析 /connections 响应；连接数组只用于计数，不对外暴露其中的敏感明细。
 * 作者：gc；创建时间：2026-10-25 21:33:34。
 */
interface MihomoConnectionsResponse {
  uploadTotal: number;
  downloadTotal: number;
  // 修改人：gc；修改时间：2026-10-25 21:47:59。
  // 修改说明：内核 Snapshot 使用未初始化的 Go 切片，无活动连接时合法编码为 null，表示真实零连接而非统计不可用。
  connections: Object[] | null;
}

export class MihomoApi {
  private secret: string;

  constructor(secret: string) {
    this.secret = secret;
  }

  private async request(path: string, method: http.RequestMethod = http.RequestMethod.GET,
    body: string = ''): Promise<string> {
    const client = http.createHttp();
    try {
      const response = await client.request(`${BASE_URL}${path}`, {
        method: method,
        header: {
          'Authorization': `Bearer ${this.secret}`,
          'Content-Type': 'application/json',
        },
        extraData: body,
        connectTimeout: 5000,
        readTimeout: 15000,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`mihomo ${method} ${path} 返回 HTTP ${response.responseCode}: ${String(response.result)}`);
      }
      return String(response.result);
    } finally {
      client.destroy();
    }
  }

  async getVersion(): Promise<MihomoVersion> {
    return JSON.parse(await this.request('/version')) as MihomoVersion;
  }

  async getConfigs(): Promise<Record<string, Object>> {
    return JSON.parse(await this.request('/configs')) as Record<string, Object>;
  }

  async setMode(mode: 'rule' | 'global' | 'direct'): Promise<void> {
    await this.request('/configs', http.RequestMethod.PATCH, JSON.stringify({ mode: mode }));
  }

  async getProxies(): Promise<ProxyList> {
    return JSON.parse(await this.request('/proxies')) as ProxyList;
  }

  async getGroups(): Promise<GroupList> {
    return JSON.parse(await this.request('/group')) as GroupList;
  }

  /**
   * 获取内核累计上传、下载字节数和当前连接数量，只返回聚合值。
   * 响应字段缺失、负数或非有限数均显式报错，不能把坏数据当成真实零流量；调用方负责采样时序。
   * 作者：gc；创建时间：2026-10-25 21:33:34。
   */
  async getTrafficTotals(): Promise<MihomoTrafficTotals> {
    const response = JSON.parse(await this.request('/connections')) as MihomoConnectionsResponse;
    if (!response || !Number.isFinite(response.uploadTotal) || response.uploadTotal < 0 ||
      !Number.isFinite(response.downloadTotal) || response.downloadTotal < 0 ||
      (response.connections !== null && !Array.isArray(response.connections))) {
      throw new Error('内核运行统计响应格式无效');
    }
    // 修改人：gc；修改时间：2026-10-25 21:47:59。
    // 修改说明：只接受内核已证实的 null 空切片；缺失、对象或其他类型仍由上方校验拒绝，不能用通用空值兜底掩盖协议错误。
    return { uploadTotal: response.uploadTotal, downloadTotal: response.downloadTotal,
      connections: response.connections === null ? 0 : response.connections.length };
  }

  async selectProxy(group: string, name: string): Promise<void> {
    await this.request(`/proxies/${encodeURIComponent(group)}`, http.RequestMethod.PUT,
      JSON.stringify({ name: name }));
  }

  async testDelay(name: string, timeout: number = 5000): Promise<number> {
    const path = `/proxies/${encodeURIComponent(name)}/delay?url=${encodeURIComponent(TEST_URL)}&timeout=${timeout}`;
    const result = JSON.parse(await this.request(path)) as Record<string, number>;
    return result.delay;
  }

  async testGroupDelay(name: string, timeout: number = 5000): Promise<Record<string, number>> {
    const path = `/group/${encodeURIComponent(name)}/delay?url=${encodeURIComponent(TEST_URL)}&timeout=${timeout}`;
    return JSON.parse(await this.request(path)) as Record<string, number>;
  }
}
