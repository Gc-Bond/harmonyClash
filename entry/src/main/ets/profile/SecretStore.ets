import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const SECRET_FILE = 'secret';

// secret 只保存在应用私有目录。失败时直接报错，绝不退回固定口令。
export function getOrCreateSecret(homeDir: string): string {
  const path = `${homeDir}/${SECRET_FILE}`;
  if (fileIo.accessSync(path)) {
    const existing = fileIo.readTextSync(path).trim();
    if (!/^[0-9a-f]{64}$/.test(existing)) {
      throw new Error('已保存的 REST secret 格式无效');
    }
    return existing;
  }

  const bytes = cryptoFramework.createRandom().generateRandomSync(32).data;
  const secret = Array.from(bytes).map((value: number) => value.toString(16).padStart(2, '0')).join('');
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, secret);
  } finally {
    fileIo.closeSync(file);
  }
  return secret;
}
