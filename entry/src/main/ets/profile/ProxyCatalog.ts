import { parse } from 'yaml';

/**
 * 本地配置中可浏览的策略组；all 只含已知本地节点、组引用和内置动作，不包含运行选择或测速结果。
 * unloadedProviders 表示 use 引用的提供者尚未读取，warnings 说明无法完整展开的原因。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
export interface ProxyCatalogGroup {
  name: string;
  type: string;
  all: string[];
  unloadedProviders: string[];
  warnings: string[];
}

/**
 * 仅从原始 Clash YAML 得到的离线目录；proxies 保留顶层本地节点顺序，groups 不合成 GLOBAL。
 * proxyTypes 不包含地址、端口或凭据；提供者不下载、不读外部文件或缓存，也不启动内核及 TUN。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
export interface ProxyCatalog {
  proxies: string[];
  groups: ProxyCatalogGroup[];
  proxyTypes: Record<string, string>;
  unloadedProviders: string[];
  warnings: string[];
}

const GROUP_TYPES: Record<string, string> = {
  select: 'Selector', 'url-test': 'URLTest', fallback: 'Fallback',
  'load-balance': 'LoadBalance', relay: 'Relay'
};
const PROXY_TYPES: Record<string, string> = {
  ss: 'Shadowsocks', ssr: 'ShadowsocksR', vmess: 'Vmess', vless: 'Vless', trojan: 'Trojan',
  socks5: 'Socks5', http: 'Http', snell: 'Snell', hysteria: 'Hysteria', hysteria2: 'Hysteria2',
  hy2: 'Hysteria2', wireguard: 'WireGuard', tuic: 'Tuic', ssh: 'Ssh', mieru: 'Mieru',
  anytls: 'AnyTLS', sudoku: 'Sudoku', masque: 'Masque', trusttunnel: 'TrustTunnel',
  shadowquic: 'ShadowQuic', direct: 'Direct', reject: 'Reject', 'reject-drop': 'RejectDrop'
};
const BUILTIN_TYPES: Record<string, string> = {
  DIRECT: 'Direct', REJECT: 'Reject', 'REJECT-DROP': 'RejectDrop', COMPATIBLE: 'Compatible',
  PASS: 'Pass', 'PASS-RULE': 'PassRule'
};

/**
 * 校验 YAML 映射结构；不将错误形状静默当成空配置，错误消息只含字段位置而不回显订阅原文。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function mapping(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} 必须是 YAML 映射`);
  }
  return value as Record<string, unknown>;
}

/**
 * 读取可选映射列表；缺省和 YAML null 对应内核 RawConfig 的空切片，其他错误类型显式失败。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function mappings(value: unknown, label: string): Record<string, unknown>[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new Error(`${label} 必须是列表`);
  return value.map((item: unknown, index: number) => mapping(item, `${label}[${index}]`));
}

/**
 * 读取名称与类型，不 trim 实际名字，避免破坏带空格的合法引用；仅拒绝缺失或空白必填字段。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function requiredText(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) throw new Error(`${label} 必须是非空字符串`);
  return value;
}

/**
 * 读取可选字符串配置；与缺省空串区分错误类型，供筛选和排除规则使用。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function optionalText(value: unknown, label: string): string {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') throw new Error(`${label} 必须是字符串`);
  return value;
}

/**
 * 验证 proxies/use 的字符串数组；引用保持 YAML 原顺序，稍后只在目录展示时合并同名成员。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function names(value: unknown, label: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new Error(`${label} 必须是字符串列表`);
  return value.map((item: unknown, index: number) => requiredText(item, `${label}[${index}]`));
}

/**
 * 读取 include-all 一类布尔开关；不把字符串 false 当成真值而虚构额外成员。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function enabled(value: unknown, label: string): boolean {
  if (value === undefined || value === null) return false;
  if (typeof value !== 'boolean') throw new Error(`${label} 必须是布尔值`);
  return value;
}

/**
 * 保留目录中同名成员首次出现的位置；显式成员与 include-all 重复不应生成两个看似独立的节点卡。
 * 这里只合并展示身份，不保证与内核兼容提供者保留的重复项计数完全一致。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function unique(values: string[]): string[] {
  return Array.from(new Set(values));
}

/**
 * 编译内核 regexp2 与 JavaScript 共同支持的名称筛选子集；支持反引号分段和前置 (?i)/(?m)/(?s)。
 * 已知会被 JS 静默误解的 .NET 锚点、字符类减法等明确拒绝；调用方给出未完整解析提示，不假装匹配成功。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function nameFilters(source: string): RegExp[] {
  return source.split('`').map((part: string) => {
    let expression = part;
    let flags = '';
    let prefix = /^\(\?([ims]+)\)/.exec(expression);
    while (prefix !== null) {
      flags += prefix[1];
      expression = expression.slice(prefix[0].length);
      prefix = /^\(\?([ims]+)\)/.exec(expression);
    }
    if (/\\[AzZGaeRKPp]|-\[|\(\?[a-zA-Z#(>]|\(\?<[^>]*-/.test(expression)) {
      throw new Error('名称筛选表达式超出离线支持范围');
    }
    return new RegExp(expression, unique(flags.split('')).join(''));
  });
}

/**
 * 对候选名称应用多个包含表达式的并集；不使用 g/y 标志，连续读取不会因 lastIndex 改变结果。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function matchesAny(value: string, filters: RegExp[]): boolean {
  return filters.some((filter: RegExp) => filter.test(value));
}

/**
 * 展开一组可在本地确定的成员。include-all 只补顶层 proxies，filter 只筛新增项；显式成员不受包含筛选影响。
 * 依据本地 mihomo outboundgroup/parser.go/groupbase.go，exclude-filter 和 exclude-type 再作用于所有成员。
 * 提供者内容不猜测，且不补内核运行时空组回退节点；未知筛选结果以空的未完整目录加 warnings 表达。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
function expandGroup(raw: Record<string, unknown>, index: number, catalog: ProxyCatalog): ProxyCatalogGroup {
  const label = `proxy-groups[${index}]`;
  const name = requiredText(raw['name'], `${label}.name`);
  const yamlType = requiredText(raw['type'], `${label}.type`);
  const type = Object.prototype.hasOwnProperty.call(GROUP_TYPES, yamlType) ? GROUP_TYPES[yamlType] : yamlType;
  const warnings: string[] = [];
  if (!Object.prototype.hasOwnProperty.call(GROUP_TYPES, yamlType)) warnings.push('此策略类型尚未确认离线语义，仅展示显式成员');
  if (yamlType === 'relay') warnings.push('当前内核已移除 relay，离线仅展示原配置的链式成员');

  const includeAll = enabled(raw['include-all'], `${label}.include-all`);
  const includeProxies = enabled(raw['include-all-proxies'], `${label}.include-all-proxies`) || includeAll;
  const includeProviders = enabled(raw['include-all-providers'], `${label}.include-all-providers`) || includeAll;
  const used = names(raw['use'], `${label}.use`);
  const unloadedProviders = unique(includeProviders ? catalog.unloadedProviders.slice().sort() : used);
  for (const provider of unloadedProviders) {
    if (!catalog.unloadedProviders.includes(provider)) throw new Error(`${label}.use 引用了未声明的提供者`);
  }
  let all = names(raw['proxies'], `${label}.proxies`);
  for (const member of all) {
    if (!Object.prototype.hasOwnProperty.call(catalog.proxyTypes, member)) {
      throw new Error(`${label}.proxies 引用了未声明的本地节点或策略组`);
    }
  }

  const filter = optionalText(raw['filter'], `${label}.filter`);
  const excludeFilter = optionalText(raw['exclude-filter'], `${label}.exclude-filter`);
  const excludeType = optionalText(raw['exclude-type'], `${label}.exclude-type`);
  let filters: RegExp[] = [];
  let filterUnavailable = false;
  if (filter && (includeProxies || unloadedProviders.length > 0)) {
    try {
      filters = nameFilters(filter);
    } catch (error) {
      filterUnavailable = true;
      warnings.push('包含筛选表达式无法离线确定，仅保留已知的显式成员');
    }
  }
  if (includeProxies && !filterUnavailable) {
    all = all.concat(catalog.proxies.slice().sort().filter((member: string) => filters.length === 0 || matchesAny(member, filters)));
  }
  // 多个提供者且存在多段包含筛选时，内核先按筛选顺序重排，再保留未匹配的显式成员；不把 provider 名当成员。
  if (unloadedProviders.length > 0 && all.length > 0 && filters.length > 1) {
    const ordered: string[] = [];
    for (const part of filters) ordered.push(...all.filter((member: string) => part.test(member)));
    all = unique(ordered.concat(all));
  }
  if (excludeFilter) {
    try {
      const excludes = nameFilters(excludeFilter);
      all = all.filter((member: string) => !matchesAny(member, excludes));
    } catch (error) {
      all = [];
      warnings.push('排除筛选表达式无法离线确定，本组成员需连接后确认');
    }
  }
  if (excludeType) {
    const excluded = excludeType.toLowerCase().split('|');
    all = all.filter((member: string) => !excluded.includes(catalog.proxyTypes[member].toLowerCase()));
  }
  if (unloadedProviders.length > 0) warnings.push('提供者内容尚未加载，离线不读取远程节点或外部缓存');
  return { name, type, all: unique(all), unloadedProviders, warnings };
}

/**
 * 解析原始 Clash YAML 为不依赖 VPN 的浏览目录；语法/结构错误显式抛出，无法完整确定的组带 warnings。
 * 使用与 RuntimeConfig 相同的 yaml 2.8 / maxAliasCount=100，并启用 Clash 常用的 YAML 合并键，不手写行匹配。
 * 不返回服务器及凭据，不写日志或文件；调用方可仅记录节点/组数量，勿记录订阅原文或筛选表达式。
 * 作者：gc；创建时间：2026-10-25 22:48:11。
 */
export function parseProxyCatalog(source: string): ProxyCatalog {
  if (source.trim().length === 0) throw new Error('本地配置内容为空');
  let parsed: unknown;
  try {
    parsed = parse(source, { maxAliasCount: 100, merge: true });
  } catch (error) {
    throw new Error('本地配置 YAML 语法无效，请检查配置格式');
  }
  const config = mapping(parsed, '本地配置');
  const proxies = mappings(config['proxies'], 'proxies');
  const rawGroups = mappings(config['proxy-groups'], 'proxy-groups');
  const providers = config['proxy-providers'] === undefined || config['proxy-providers'] === null ?
    {} : mapping(config['proxy-providers'], 'proxy-providers');
  for (const name of Object.keys(providers)) mapping(providers[name], 'proxy-providers 项');

  const catalog: ProxyCatalog = {
    proxies: [], groups: [], proxyTypes: Object.assign(Object.create(null), BUILTIN_TYPES),
    unloadedProviders: Object.keys(providers), warnings: []
  };
  for (let index = 0; index < proxies.length; index++) {
    const name = requiredText(proxies[index]['name'], `proxies[${index}].name`);
    const type = requiredText(proxies[index]['type'], `proxies[${index}].type`).toLowerCase();
    if (Object.prototype.hasOwnProperty.call(catalog.proxyTypes, name)) throw new Error('本地节点名称与节点或内置动作重复');
    catalog.proxies.push(name);
    catalog.proxyTypes[name] = Object.prototype.hasOwnProperty.call(PROXY_TYPES, type) ? PROXY_TYPES[type] : type.toUpperCase();
  }
  for (let index = 0; index < rawGroups.length; index++) {
    const name = requiredText(rawGroups[index]['name'], `proxy-groups[${index}].name`);
    const type = requiredText(rawGroups[index]['type'], `proxy-groups[${index}].type`);
    if (Object.prototype.hasOwnProperty.call(catalog.proxyTypes, name)) throw new Error('本地策略组名称与节点或内置动作重复');
    catalog.proxyTypes[name] = Object.prototype.hasOwnProperty.call(GROUP_TYPES, type) ? GROUP_TYPES[type] : type;
  }
  catalog.groups = rawGroups.map((group: Record<string, unknown>, index: number) => expandGroup(group, index, catalog));
  for (const group of catalog.groups) {
    for (const warning of group.warnings) catalog.warnings.push(`${group.name}：${warning}`);
  }
  if (catalog.unloadedProviders.length > 0 && catalog.groups.length === 0) {
    catalog.warnings.push('提供者内容尚未加载，本地目录不包含其远程节点');
  }
  return catalog;
}
