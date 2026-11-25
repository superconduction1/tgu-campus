// 断点续传下载 Flutter Windows SDK（只为本地 dart analyze / flutter analyze 用）。
// 用法：node tools/fetch-flutter.mjs [--force]
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..');
const TOOLS = path.join(ROOT, '.tools');
const ZIP = path.join(TOOLS, 'flutter_sdk.zip');
const RELEASES = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json';

const STALL_MS = 45_000;
const CHUNK = 1 << 20;

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

async function pickRelease() {
  const res = await fetch(RELEASES, { headers: { 'user-agent': 'curl/8' } });
  if (!res.ok) throw new Error(`releases.json HTTP ${res.status}`);
  const json = await res.json();
  const stable = json.releases.filter((r) => r.channel === 'stable' && r.archive.endsWith('.zip'));
  const cur = stable.find((r) => r.hash === json.current_release.stable);
  if (!cur) throw new Error('没找到当前 stable');
  return {
    url: `${json.base_url}/${cur.archive}`,
    version: cur.version,
    sha256: cur.sha256,
    size: Number(cur.archive_size || 0),
  };
}

function human(n) {
  return `${(n / 1048576).toFixed(1)}MB`;
}

async function download(url, total) {
  fs.mkdirSync(TOOLS, { recursive: true });
  let have = fs.existsSync(ZIP) ? fs.statSync(ZIP).size : 0;
  if (total && have >= total) {
    log(`已完整（${human(have)}），跳过下载`);
    return;
  }
  let tries = 0;
  let lastProgress = Date.now();
  let lastBytes = have;
  let lastLog = 0;

  while (true) {
    if (total && have >= total) break;
    tries += 1;
    if (tries > 200) throw new Error('重试次数超限');
    const headers = { 'user-agent': 'curl/8', accept: '*/*' };
    if (have > 0) headers.range = `bytes=${have}-`;
    let res;
    try {
      res = await fetch(url, { headers, redirect: 'follow' });
    } catch (e) {
      log(`连接失败 ${e.message}，2s 后重试（第 ${tries} 次）`);
      await new Promise((r) => setTimeout(r, 2000));
      continue;
    }
    if (res.status === 416) {
      log('服务端说范围已满足，视为完成');
      break;
    }
    if (!(res.status === 206 || res.status === 200)) {
      log(`HTTP ${res.status}，2s 后重试`);
      await new Promise((r) => setTimeout(r, 2000));
      continue;
    }
    if (res.status === 200 && have > 0) {
      log('服务端不支持 Range，从头写');
      have = 0;
    }
    const fd = fs.openSync(ZIP, have > 0 ? 'a' : 'w');
    let stallTimer = null;
    const arm = () => {
      clearTimeout(stallTimer);
      stallTimer = setTimeout(() => {
        log('卡住超过 45s，断开重连');
        try { fd.closeSync(fd); } catch {}
      }, STALL_MS);
    };
    arm();
    try {
      for await (const chunk of res.body) {
        arm();
        fs.writeSync(fd, chunk);
        have += chunk.length;
        lastBytes = have;
        lastProgress = Date.now();
        if (Date.now() - lastLog > 5000) {
          lastLog = Date.now();
          const speed = (have - lastBytes) / Math.max(1, (lastLog - lastProgress)) * 1000;
          const pct = total ? ` (${((have / total) * 100).toFixed(1)}%)` : '';
          log(`${human(have)}${pct} ${human(speed)}/s`);
          lastProgress = lastLog;
          lastBytes = have;
        }
        if (total && have >= total) break;
      }
    } catch (e) {
      log(`流中断 ${e.message}`);
    } finally {
      clearTimeout(stallTimer);
      try { fd.closeSync(); } catch {}
    }
    if (total && have >= total) break;
    if (Date.now() - lastProgress > 10_000) log(`续传点 ${human(lastBytes)}`);
  }
  log(`下载结束：${human(fs.statSync(ZIP).size)}`);
}

async function sha256(file) {
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    const s = fs.createReadStream(file);
    s.on('data', (d) => h.update(d));
    s.on('end', () => resolve(h.digest('hex')));
    s.on('error', reject);
  });
}

const rel = await pickRelease();
log(`目标版本 ${rel.version}，${rel.size ? human(rel.size) : '大小未知'}`);
log(rel.url);
await download(rel.url, rel.size);

if (rel.sha256) {
  log('校验 sha256 …');
  const got = await sha256(ZIP);
  if (got !== rel.sha256) {
    log(`校验失败：期望 ${rel.sha256}，实际 ${got}`);
    log('删除 zip，请重跑本脚本');
    fs.unlinkSync(ZIP);
    process.exit(2);
  }
  log('sha256 一致');
}
log('完成');
