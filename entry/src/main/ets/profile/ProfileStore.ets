import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { validateProfile } from './RuntimeConfig';

const PROFILE_DIR = 'profiles';
const INDEX_FILE = 'profiles.json';
const MAX_PROFILE_LENGTH = 10 * 1024 * 1024;

export class Profile {
  id: string = '';
  name: string = '';
  url: string = '';
  updatedAt: number = 0;
  upload: number = 0;
  download: number = 0;
  total: number = 0;
  expire: number = 0;
}

class ProfileIndex {
  profiles: Profile[] = [];
  activeId: string = '';
}

interface FetchResult {
  source: string;
  info: Record<string, number>;
}

export function writeAtomic(path: string, content: string): void {
  const temp = `${path}.${util.generateRandomUUID()}.tmp`;
  const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, content);
  } finally {
    fileIo.closeSync(file);
  }
  try {
    fileIo.renameSync(temp, path);
  } catch (error) {
    fileIo.unlinkSync(temp);
    throw error as Error;
  }
}

function subscriptionInfo(headers: Record<string, Object>): Record<string, number> {
  let value = '';
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === 'subscription-userinfo') {
      value = String(headers[key]);
      break;
    }
  }
  const result: Record<string, number> = {};
  for (const item of value.split(';')) {
    const pair = item.trim().split('=');
    if (pair.length === 2 && /^(upload|download|total|expire)$/.test(pair[0])) {
      const number = Number(pair[1]);
      if (Number.isFinite(number) && number >= 0) {
        result[pair[0]] = number;
      }
    }
  }
  return result;
}

export class ProfileStore {
  private homeDir: string;

  constructor(homeDir: string) {
    this.homeDir = homeDir;
  }

  private indexPath(): string {
    return `${this.homeDir}/${INDEX_FILE}`;
  }

  private profilePath(id: string): string {
    // id 由 UUID 生成；读取旧索引时也验证，避免坏数据变成任意路径。
    if (!/^[0-9a-f-]{36}$/.test(id)) {
      throw new Error('订阅 ID 无效');
    }
    return `${this.homeDir}/${PROFILE_DIR}/${id}.yaml`;
  }

  private load(): ProfileIndex {
    if (!fileIo.accessSync(this.indexPath())) {
      return new ProfileIndex();
    }
    const value = JSON.parse(fileIo.readTextSync(this.indexPath())) as ProfileIndex;
    if (!Array.isArray(value.profiles) || typeof value.activeId !== 'string') {
      throw new Error('订阅索引格式无效');
    }
    return value;
  }

  private save(index: ProfileIndex): void {
    writeAtomic(this.indexPath(), JSON.stringify(index));
  }

  list(): Profile[] {
    return this.load().profiles;
  }

  active(): Profile | undefined {
    const index = this.load();
    return index.profiles.find((profile: Profile) => profile.id === index.activeId);
  }

  setActive(id: string): void {
    const index = this.load();
    if (!index.profiles.some((profile: Profile) => profile.id === id)) {
      throw new Error('订阅不存在');
    }
    index.activeId = id;
    this.save(index);
  }

  activeYaml(): string {
    const profile = this.active();
    return profile ? fileIo.readTextSync(this.profilePath(profile.id)) : '';
  }

  importText(name: string, source: string): Profile {
    return this.store(name, '', source, {});
  }

  async importUrl(name: string, url: string): Promise<Profile> {
    if (!/^https?:\/\/[^\s]+$/i.test(url)) {
      throw new Error('订阅地址必须是 HTTP 或 HTTPS URL');
    }
    const response = await this.fetch(url);
    return this.store(name, url, response.source, response.info);
  }

  async update(id: string): Promise<Profile> {
    const profile = this.load().profiles.find((item: Profile) => item.id === id);
    if (!profile || !profile.url) {
      throw new Error('这条订阅不能从 URL 更新');
    }
    const response = await this.fetch(profile.url);
    return this.store(profile.name, profile.url, response.source, response.info, id);
  }

  private async fetch(url: string): Promise<FetchResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'clash-verge' },
        connectTimeout: 10000,
        readTimeout: 30000,
        maxLimit: MAX_PROFILE_LENGTH,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`下载订阅失败: HTTP ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error('订阅响应不是文本');
      }
      return { source: response.result, info: subscriptionInfo(response.header as Record<string, Object>) };
    } finally {
      request.destroy();
    }
  }

  private store(name: string, url: string, source: string, info: Record<string, number>,
    existingId: string = ''): Profile {
    if (!name.trim()) {
      throw new Error('订阅名称不能为空');
    }
    if (source.length === 0 || source.length > MAX_PROFILE_LENGTH) {
      throw new Error('订阅内容为空或超过 10 MiB');
    }
    validateProfile(source);
    const index = this.load();
    const profile = existingId
      ? index.profiles.find((item: Profile) => item.id === existingId)
      : undefined;
    if (existingId && !profile) {
      throw new Error('订阅不存在');
    }
    const item = profile ?? new Profile();
    item.id = existingId || util.generateRandomUUID();
    item.name = name.trim();
    item.url = url;
    item.updatedAt = Date.now();
    item.upload = info.upload ?? 0;
    item.download = info.download ?? 0;
    item.total = info.total ?? 0;
    item.expire = info.expire ?? 0;

    if (!fileIo.accessSync(`${this.homeDir}/${PROFILE_DIR}`)) {
      fileIo.mkdirSync(`${this.homeDir}/${PROFILE_DIR}`);
    }
    writeAtomic(this.profilePath(item.id), source);
    if (!profile) {
      index.profiles.push(item);
      if (!index.activeId) {
        index.activeId = item.id;
      }
    }
    this.save(index);
    return item;
  }
}
