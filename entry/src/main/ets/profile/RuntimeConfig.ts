import { parse, stringify } from 'yaml';

export type RuntimeMode = 'rule' | 'global' | 'direct';

const DEFAULT_DNS = {
  'enable': true,
  'ipv6': false,
  'enhanced-mode': 'fake-ip',
  'fake-ip-range': '198.18.0.1/16',
  'default-nameserver': ['223.5.5.5', '119.29.29.29'],
  'nameserver': ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query'],
};

function asMapping(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} 必须是 YAML 映射`);
  }
  return value as Record<string, unknown>;
}

// 订阅的代理、规则和提供者原样保留；运行时只覆盖本应用负责的监听与控制项。
export function buildRuntimeConfig(source: string, secret: string, mode: RuntimeMode): string {
  const parsed = source.trim() === '' ? {} : parse(source, { maxAliasCount: 100 });
  const config = asMapping(parsed, '订阅配置');
  const dns = config['dns'] === undefined ? {} : asMapping(config['dns'], 'dns');
  const tun = config['tun'] === undefined ? {} : asMapping(config['tun'], 'tun');

  config['mixed-port'] = 7890;
  config['allow-lan'] = false;
  config['external-controller'] = '127.0.0.1:9090';
  config['secret'] = secret;
  config['mode'] = mode;
  config['find-process-mode'] = 'always';
  config['tun'] = { ...tun, enable: false };
  config['dns'] = { ...DEFAULT_DNS, ...dns, enable: true };
  return stringify(config);
}

export function validateProfile(source: string): void {
  asMapping(parse(source, { maxAliasCount: 100 }), '订阅配置');
}
