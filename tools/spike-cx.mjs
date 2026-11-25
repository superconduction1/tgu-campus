// 学习通（超星）校准工具：登录后把能碰到的页面全抓一遍，找作业列表和图书馆座位预约的真实接口。
// 用法：node tools/spike-cx.mjs  然后浏览器打开 http://127.0.0.1:8788 输入手机号+密码。
// 产物：dump-cx/*.html / *.json，以及页面上的抓取报告。
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'dump-cx');
const PORT = Number(process.env.SPIKE_PORT || 8788);
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// ---------- 学习通密码加密：AES-128-CBC，key 与 IV 同为 u2oh6Vu^HWe4_AES ----------
const AES_KEY = Buffer.from('u2oh6Vu^HWe4_AES', 'utf8');
function aesEncrypt(plain) {
  const c = crypto.createCipheriv('aes-128-cbc', AES_KEY, AES_KEY);
  return Buffer.concat([c.update(plain, 'utf8'), c.final()]).toString('base64');
}

// ---------- Cookie jar（超星的 cookie 基本都挂在 .chaoxing.com 上，用单表足够） ----------
const jar = new Map(); // name -> value

function storeCookies(setCookie) {
  if (!setCookie) return;
  for (const line of [].concat(setCookie)) {
    const first = line.split(';')[0];
    const eq = first.indexOf('=');
    if (eq <= 0) continue;
    const name = first.slice(0, eq).trim();
    const value = first.slice(eq + 1).trim();
    if (!name) continue;
    if (/^(expires|max-age)$/i.test(value)) continue;
    if (/^(deleted|"")$/.test(value)) { jar.delete(name); continue; }
    jar.set(name, value);
  }
}

function cookieHeader() {
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}

function isCxHost(host) {
  return /(^|\.)chaoxing\.(com|cn)$/i.test(host) || /(^|\.)chaoxing\.com$/i.test(host);
}

// ---------- 带 Cookie、自动跟跳转的请求 ----------
async function fetchHop(url, opts = {}, hops = 0) {
  if (hops > 4) return { url, status: 0, headers: {}, body: '', note: 'too many redirects' };
  let res;
  try {
    res = await fetch(url, {
      method: opts.method || 'GET',
      headers: {
        'User-Agent': UA,
        'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        ...(jar.size ? { Cookie: cookieHeader() } : {}),
        ...(opts.headers || {}),
      },
      body: opts.body,
      redirect: 'manual',
    });
  } catch (e) {
    return { url, status: 0, headers: {}, body: '', note: `network: ${e.message}` };
  }
  storeCookies(res.headers.getSetCookie ? res.headers.getSetCookie() : res.headers.get('set-cookie'));
  const loc = res.headers.get('location');
  if (res.status >= 300 && res.status < 400 && loc) {
    const next = new URL(loc, url).toString();
    // 登录跳转链路上别跟丢，但也不要无限跟
    if (/\/logout|signout/i.test(next)) {
      return { url, status: res.status, headers: res.headers, body: '', note: `redirect to ${next} (stopped)` };
    }
    return fetchHop(next, { method: 'GET' }, hops + 1);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  return {
    url,
    status: res.status,
    headers: Object.fromEntries(res.headers.entries()),
    body: decodeBody(buf, res.headers.get('content-type') || ''),
    bytes: buf.length,
  };
}

// 超星的编码很乱：多数页面其实是 UTF-8（哪怕 meta 写 gbk），少数真是 GBK。
// 所以先按 UTF-8 严格解一遍——能解通就是 UTF-8；解不通再退回声明/GBK。
// 千万别只看 content-type 或 meta，两头都会骗人。
function decodeBody(buf, contentType) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch { /* 不是合法 UTF-8，继续 */ }
  const head = buf.subarray(0, 2048).toString('latin1');
  let enc = (String(contentType).match(/charset=["']?([\w-]+)/i) || [])[1]
    || (head.match(/charset=["']?([\w-]+)/i) || [])[1]
    || 'gbk';
  try {
    return new TextDecoder(enc.toLowerCase()).decode(buf);
  } catch {
    return buf.toString('utf8');
  }
}

function form(obj) {
  return Object.entries(obj)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v ?? '')}`)
    .join('&');
}

// ---------- 登录 ----------
const LOGIN_PAGE = 'https://passport2.chaoxing.com/login?fid=&refer=https%3A%2F%2Fi.chaoxing.com';
const REFER = 'https%3A%2F%2Fi.chaoxing.com';

async function login(uname, password) {
  const page = await fetchHop(LOGIN_PAGE);
  const html = page.body || '';
  const m = html.match(/id=["']t["'][^>]*value=["']([^"']*)["']/i)
    || html.match(/value=["']([^"']*)["'][^>]*id=["']t["']/i);
  const needEncrypt = (m ? m[1] : 'true') !== 'false';
  const pwd = needEncrypt ? aesEncrypt(password) : password;

  const res = await fetchHop('https://passport2.chaoxing.com/fanyalogin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest', 'Referer': LOGIN_PAGE },
    body: form({
      fid: '-1',
      uname,
      password: pwd,
      refer: REFER,
      t: needEncrypt ? 'true' : 'false',
      forbidotherlogin: '0',
      validate: '',
      doubleFactorLogin: '0',
      independentId: '0',
      independentNameId: '0',
    }),
  });

  let data = null;
  try { data = JSON.parse(res.body); } catch { /* 不是 JSON 就保留原文 */ }
  const ok = !!(data && (data.status === true || data.status === 'true'));
  return { ok, data, raw: res.body.slice(0, 400), needEncrypt, url: data && data.url ? safeDecode(data.url) : '' };
}

// ---------- 抓取 ----------
const SKIP = /logout|signout|exit|passport2\.chaoxing\.com\/(login|fanyalogin)|javascript:|mailto:|\.(js|css|png|jpe?g|gif|svg|woff2?|ttf|ico)(\?|$)/i;
const PRIORITY = /work|homework|作业|seat|座位|预约|图书馆|library|exam|考试|job|todo|待办/i;

const SEEDS = [
  'https://i.chaoxing.com/',
  'https://mooc1.chaoxing.com/visit/interaction',
  'https://mooc1.chaoxing.com/',
];

function extractLinks(html, baseUrl) {
  const out = new Set();
  const re = /href\s*=\s*["']([^"']+)["']/gi;
  let m;
  while ((m = re.exec(html))) {
    const raw = m[1].trim();
    if (!raw || raw.startsWith('#') || SKIP.test(raw)) continue;
    let abs;
    try { abs = new URL(raw, baseUrl).toString(); } catch { continue; }
    if (!/^https?:/i.test(abs)) continue;
    let host;
    try { host = new URL(abs).host; } catch { continue; }
    if (!isCxHost(host)) continue;
    if (SKIP.test(abs)) continue;
    out.add(abs.split('#')[0]);
  }
  return [...out];
}

function slug(url) {
  return url.replace(/^https?:\/\//, '').replace(/[^\w.\-]+/g, '_').slice(0, 90);
}

/// 登录接口返回的 url 有时已经被 URL 编码过一次，直接用会请求到
/// `https%3A%2F%2Fi.chaoxing.com` 这种地址（第一轮就踩了这个坑）。
function safeDecode(url) {
  if (!/%2F|%3A/i.test(url)) return url;
  try {
    return decodeURIComponent(url);
  } catch {
    return url;
  }
}

const report = [];

async function crawl(extraSeeds = []) {
  fs.mkdirSync(OUT, { recursive: true });
  report.length = 0;
  const seen = new Set();
  // 登录成功返回的 url 带着会话参数，是最可靠的入口；排在种子前面
  const queue = [...new Set([...extraSeeds.filter(Boolean), ...SEEDS])].map(u => ({ url: u, depth: 0 }));
  let n = 0;

  while (queue.length && n < 45) {
    // 优先抓疑似作业/座位的链接
    queue.sort((a, b) => (PRIORITY.test(b.url) ? 1 : 0) - (PRIORITY.test(a.url) ? 1 : 0));
    const { url, depth } = queue.shift();
    const key = url.split('#')[0];
    if (seen.has(key)) continue;
    seen.add(key);

    const r = await fetchHop(url);
    n += 1;
    const isJson = /json/i.test(r.headers['content-type'] || '') || /^[\s]*[[{]/.test((r.body || '').slice(0, 40));
    const ext = isJson ? 'json' : 'html';
    const file = `${String(n).padStart(2, '0')}_${slug(url)}.${ext}`;
    fs.writeFileSync(path.join(OUT, file), r.body || '', 'utf8');

    const hits = [...new Set((r.body || '').match(new RegExp(PRIORITY.source, 'gi')) || [])].slice(0, 8);
    report.push({
      n, url, status: r.status, bytes: r.bytes || (r.body || '').length,
      file, isJson, depth, hits, note: r.note || '',
    });

    if (!isJson && depth < 2 && (r.body || '').length < 400000) {
      for (const link of extractLinks(r.body || '', url)) {
        if (!seen.has(link)) queue.push({ url: link, depth: depth + 1 });
      }
    }
  }
  const summary = {
    total: report.length,
    json: report.filter(x => x.isJson).length,
    withHits: report.filter(x => x.hits.length).length,
    non200: report.filter(x => x.status !== 200).length,
  };
  fs.writeFileSync(path.join(OUT, '_report.json'), JSON.stringify({ summary, report }, null, 2), 'utf8');
  return summary;
}

// ---------- 第二阶段：直接点名抓作业列表 ----------
// 课程页里「作业」那一项是 <a data-url="https://mooc1.chaoxing.com/mooc2/work/list">，
// 参数取自该页自己的 courseId / clazzId / cpi，所以在页面里能凑出来。
const WORK_LIST = 'https://mooc1.chaoxing.com/mooc2/work/list';

function writeReport() {
  const summary = {
    total: report.length,
    json: report.filter(x => x.isJson).length,
    withHits: report.filter(x => x.hits.length).length,
    non200: report.filter(x => x.status !== 200).length,
  };
  fs.writeFileSync(path.join(OUT, '_report.json'), JSON.stringify({ summary, report }, null, 2), 'utf8');
  return summary;
}

// 课程页里的隐藏域，导航脚本就是读这些值拼 URL 的：
//   var courseid = $("#courseid").val(); ... var enc = $("#oldenc").val();
// 作业那一路的拼法是
//   url = data-url + "?courseId=" + courseid + "&classId=" + clazzid + "&cpi=" + cpi + "&ut=s"
//   然后补 "&t=" + t，最后统一加 "&stuenc=" + enc
function hiddenValue(html, id) {
  const a = new RegExp(`<input[^>]*id=["']${id}["'][^>]*value=["']([^"']*)["']`, 'i');
  const b = new RegExp(`<input[^>]*value=["']([^"']*)["'][^>]*id=["']${id}["']`, 'i');
  const m = html.match(a) || html.match(b);
  return m ? m[1] : '';
}

function courseContexts() {
  const found = new Map();
  for (const r of report) {
    if (r.isJson || !r.file) continue;
    let html = '';
    try { html = fs.readFileSync(path.join(OUT, r.file), 'utf8'); } catch { continue; }
    const courseId = hiddenValue(html, 'courseid');
    if (!courseId || found.has(courseId)) continue;
    found.set(courseId, {
      courseId,
      clazzId: hiddenValue(html, 'clazzid'),
      cpi: hiddenValue(html, 'cpi'),
      t: hiddenValue(html, 't'),
      // course-stu.js 里 stuenc 取的是 #enc，enc= 取的是 #workEnc，两者不同值。
      enc: hiddenValue(html, 'enc'),
      workEnc: hiddenValue(html, 'workEnc'),
      openc: hiddenValue(html, 'openc'),
      from: r.file,
    });
  }
  return [...found.values()].slice(0, 15);
}

async function grabExtra(url, tag) {
  const r = await fetchHop(url);
  const body = r.body || '';
  if (!body) return { status: r.status, note: r.note || 'empty', file: '' };
  const isJson = /json/i.test(r.headers['content-type'] || '') || /^[\s]*[[{]/.test(body.slice(0, 40));
  const n = report.length + 1;
  const file = `x${String(n).padStart(2, '0')}_${tag}_${slug(url)}.${isJson ? 'json' : 'html'}`;
  fs.writeFileSync(path.join(OUT, file), body, 'utf8');
  const hits = [...new Set(body.match(new RegExp(PRIORITY.source, 'gi')) || [])].slice(0, 8);
  report.push({ n, url, status: r.status, bytes: body.length, file, isJson, depth: 0, hits, note: r.note || '' });
  return { status: r.status, file, hits, bytes: body.length, body };
}

async function phase2WorkLists() {
  const ctxs = courseContexts();
  if (!ctxs.length) {
    console.log('[phase2] 页面里没解析到课程隐藏域，跳过作业列表');
    return;
  }
  console.log(`[phase2] 按 ${ctxs.length} 门课抓作业列表（按 course-stu.js 的 zy 分支拼）`);
  for (const c of ctxs) {
    // 逐字对照 course-stu.js：
    //   ?courseId=&classId=&cpi=&ut=s  &enc=<workEnc>  &t=<t>  &stuenc=<enc>
    const base = `courseId=${c.courseId}&classId=${c.clazzId}&cpi=${c.cpi}&ut=s`
      + (c.workEnc ? `&enc=${c.workEnc}` : '')
      + (c.t ? `&t=${c.t}` : '');
    for (const [tag, qs] of [
      ['work', `${base}&stuenc=${c.enc}`],   // 完整签名
      ['worknoenc', base],                    // 去掉 stuenc，做对照
    ]) {
      if (tag === 'work' && !c.enc) continue;
      const r = await grabExtra(`${WORK_LIST}?${qs}`, `${tag}_${c.courseId}`);
      const text = (r.body || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
      console.log(`[phase2] ${c.courseId}/${tag} -> ${r.status} ${r.file || r.note} ${text}`);
    }
  }
}

// ---------- 座位预约探测 ----------
// 用户在 App 里能看到「座位预约」，但网页版 i.chaoxing.com 没有这个入口，
// 所以拿不到地址，只能「猜路径 + 用他的登录态验证」。
// 已知：mh 平台的应用上下文路径是 /entry/（404 JSON 里回 "path":"/entry/seat/index"），
//       且 /entry/index 未登录时 302 到 v1.chaoxing.com 登录网关。
// 登录成功后再打一遍，如果 200 且正文里有「座位/预约」，就说明猜对了。
const SEAT_CANDIDATES = [
  'https://seat.mh.chaoxing.com/entry/index',
  'https://seat.mh.chaoxing.com/entry/index?fid=2276',
  'https://seat.mh.chaoxing.com/entry/index?fid=27727',
  'https://seat.mh.chaoxing.com/entry/seat/index',
  'https://seat.mh.chaoxing.com/entry/zuowei/index',
  'https://seat.mh.chaoxing.com/seat/index',
  'https://tsg.mh.chaoxing.com/entry/index',
  'https://mh.chaoxing.com/entry/index',
];

function lookLikeLogin(body) {
  return /passport2\.chaoxing\.com|请登录|用户登录|fanyalogin/i.test(body || '');
}

// mh 平台的机构应用是带令牌的：/engine2/general/more?t=<一串大写十六进制>，
// 令牌每校每应用唯一，猜不出来。所以先扫已登录页面里有没有这种链接。
const APP_LINK_RE = /(https?:\/\/[a-z0-9.\-]+\.mh\.chaoxing\.com\/engine2\/general\/more\?t=[A-Za-z0-9]+)/gi;

async function scanSeatEntry() {
  const seeds = [
    'https://v1.chaoxing.com',
    'https://i.chaoxing.com',
    'https://mooc1.chaoxing.com/visit/interaction',
  ];
  const links = new Set();
  for (const url of seeds) {
    let r;
    try {
      r = await grabExtra(url, 'scan');
    } catch (e) {
      console.log(`[phase3] scan ERR ${url} ${e.message}`);
      continue;
    }
    const body = r.body || '';
    for (const m of body.matchAll(APP_LINK_RE)) links.add(m[1]);
    const seatWords = (body.match(/座位|预约/g) || []).length;
    console.log(
      `[phase3] scan ${url} -> ${r.status} ${body.length}B 座位/预约 ${seatWords} 处，累计应用链接 ${links.size} 个`,
    );
  }
  if (links.size) {
    console.log('[phase3] 发现应用链接：');
    for (const l of links) console.log('   ' + l);
  } else {
    console.log('[phase3] 这三个页面里没有 /engine2/general/more?t= 形式的链接');
  }
  return [...links];
}

async function phase3SeatProbe() {
  console.log('[phase3] 先扫登录后的页面，找带令牌的机构应用链接');
  const discovered = await scanSeatEntry();

  console.log(`[phase3] 座位预约探测：${SEAT_CANDIDATES.length} 个候选地址`);
  let hit = null;
  for (const url of SEAT_CANDIDATES) {
    try {
      const r = await grabExtra(url, 'seat');
      const body = r.body || '';
      const text = body.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 50);
      const needsLogin = lookLikeLogin(body);
      const seatish = /座位|预约/.test(body);
      if (seatish && !needsLogin && !hit) hit = { url, file: r.file };
      console.log(
        `[phase3] ${r.status} ${seatish && !needsLogin ? '★命中' : needsLogin ? '要登录' : '      '} ` +
          `${url} -> ${r.file || r.note} ${text}`,
      );
    } catch (e) {
      console.log(`[phase3] ERR ${url} ${e.message}`);
    }
  }
  if (hit) console.log(`[phase3] 命中：${hit.url}（存到 ${hit.file}）`);
  else console.log(`[phase3] ${SEAT_CANDIDATES.length} 个候选都没命中，需要用户从 App 里把地址抄出来`);
  return { hit, discovered };
}

// ---------- Web UI ----------
let lastLogin = null;

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const STYLE = `<style>
body{font:14px/1.6 -apple-system,"Segoe UI",system-ui,sans-serif;max-width:1080px;margin:32px auto;padding:0 20px;color:#1b1b1f;background:#fafafa}
h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px}
.muted{color:#6b6b76;font-size:13px}
input{width:100%;padding:9px 11px;border:1px solid #d0d0d8;border-radius:7px;font-size:14px;box-sizing:border-box;background:#fff}
label{display:block;margin:12px 0 4px;font-weight:600;font-size:13px}
button{margin-top:18px;padding:10px 20px;border:0;border-radius:7px;background:#2b5cff;color:#fff;font-size:14px;cursor:pointer}
button:hover{background:#1e46cc}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #e3e3ea;border-radius:8px;overflow:hidden}
th,td{padding:7px 10px;border-bottom:1px solid #eee;text-align:left;font-size:13px;vertical-align:top}
th{background:#f2f2f6;font-weight:600}
tr:last-child td{border-bottom:0}
code{background:#eeeef4;padding:1px 5px;border-radius:4px;font-size:12px;word-break:break-all}
.ok{color:#127a3a;font-weight:600}.bad{color:#c02020;font-weight:600}
.box{background:#fff;border:1px solid #e3e3ea;border-radius:9px;padding:16px 18px;margin:14px 0}
</style>`;

function page(title, body) {
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>${esc(title)}</title>${STYLE}<body>${body}</body></html>`;
}

function renderForm(msgHtml = '') {
  return page('学习通校准工具', `
<h1>学习通校准工具</h1>
<p class="muted">用你自己的学习通账号登录，只在本机跑。账号密码不会写到磁盘，只存在内存里发一次登录请求。</p>
${msgHtml}
<form method="POST" action="/login">
  <label>手机号 / 学号</label>
  <input name="uname" autocomplete="username" required>
  <label>密码</label>
  <input name="password" type="password" autocomplete="current-password" required>
  <button type="submit">登录并抓取</button>
</form>
<div class="box muted" style="margin-top:26px">
抓取内容：学习通首页、我的课程、以及所有能在页面里点到的链接（最多 45 个），
<strong>会跳过所有登出链接</strong>。剩下的交给报告。
</div>`);
}

function renderReport(msgHtml = '') {
  if (!lastLogin) return renderForm();
  const s = lastLogin.summary || {};
  const rows = report.map(r => `<tr>
    <td>${r.n}</td>
    <td><code>${esc(r.url)}</code></td>
    <td class="${r.status === 200 ? 'ok' : 'bad'}">${r.status}</td>
    <td>${r.bytes}</td>
    <td>${r.hits.length ? r.hits.map(h => `<code>${esc(h)}</code>`).join(' ') : '<span class="muted">—</span>'}</td>
  </tr>`).join('');

  const jsonOnes = report.filter(r => r.isJson).map(r => `<li><code>${esc(r.url)}</code><br><span class="muted">${esc(r.file)}</span></li>`).join('');
  const hitOnes = report.filter(r => r.hits.length).map(r => `<li><code>${esc(r.url)}</code><br><span class="muted">命中：${esc(r.hits.join(', '))} → ${esc(r.file)}</span></li>`).join('');

  return page('学习通抓取报告', `
<h1>抓取完成</h1>
<p class="muted">共 ${s.total || 0} 个页面，其中 JSON ${s.json || 0} 个，含关键词 ${s.withHits || 0} 个，非 200 的 ${s.non200 || 0} 个。</p>
<p class="muted">产物目录：<code>${esc(OUT)}</code></p>
${msgHtml}

<h2>补抓（作业列表 / 手动指定网址）</h2>
${(() => {
    const extra = report.filter(r => /^x\d/.test(r.file || ''));
    if (!extra.length) return '<p class="muted">这一轮没有补抓。</p>';
    return `<ul>${extra.map(r => `<li><code>${esc(r.url)}</code><br><span class="muted">${r.status} · ${r.bytes} 字节 · 命中：${esc(r.hits.join(', ') || '无')} → ${esc(r.file)}</span></li>`).join('')}</ul>`;
  })()}
<form method="POST" action="/manual">
  <label>再抓一个网址（比如手机上「座位预约」的地址，原样粘进来）</label>
  <input name="url" placeholder="https://..." required>
  <button type="submit">抓这个页面</button>
</form>

<h2>JSON 响应（最可能是真实接口）</h2>
${jsonOnes ? `<ul>${jsonOnes}</ul>` : '<p class="muted">没有抓到 JSON。学习通的作业列表可能是服务端渲染的 HTML，看下面的关键词命中。</p>'}

<h2>命中作业 / 座位 / 图书馆关键词</h2>
${hitOnes ? `<ul>${hitOnes}</ul>` : '<p class="muted">没有命中。说明这些功能在 App 原生页面里，走的是独立 API，需要额外抓包。</p>'}

<h2>全部请求</h2>
<table><tr><th>#</th><th>URL</th><th>状态</th><th>字节</th><th>关键词</th></tr>${rows}</table>`);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const send = (code, body, type = 'text/html; charset=utf-8') => {
    res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(body);
  };

  if (req.method === 'GET' && url.pathname === '/') return send(200, renderForm(lastLogin && lastLogin.ok ? '' : ''));
  if (req.method === 'GET' && url.pathname === '/report') return send(200, renderReport());

  if (req.method === 'POST' && url.pathname === '/login') {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = new URLSearchParams(Buffer.concat(chunks).toString('utf8'));
    const uname = (body.get('uname') || '').trim();
    const password = body.get('password') || '';
    if (!uname || !password) return send(400, renderForm('<p class="bad">账号或密码为空。</p>'));

    console.log(`[login] ${uname}`);
    try {
      const r = await login(uname, password);
      lastLogin = r;
      if (!r.ok) {
        const msg = (r.data && (r.data.msg2 || r.data.msg || r.data.mes)) || r.raw || '登录失败（无返回信息）';
        console.log(`[login] failed: ${msg}`);
        return send(200, renderForm(`<div class="box"><span class="bad">登录失败：</span>${esc(msg)}</div>`));
      }
      console.log('[login] ok, crawling…');
      const summary = await crawl(r.url ? [r.url] : []);
      lastLogin.summary = summary;
      console.log(`[crawl] ${summary.total} pages, ${summary.json} json`);
      await phase2WorkLists();
      lastLogin.seat = await phase3SeatProbe();
      lastLogin.summary = writeReport();
      console.log(`[done] ${report.length} 个请求`);
      res.writeHead(302, { Location: '/report' });
      return res.end();
    } catch (e) {
      console.error('[error]', e);
      return send(500, renderForm(`<p class="bad">出错了：${esc(e.message)}</p>`));
    }
  }

  if (req.method === 'POST' && url.pathname === '/manual') {
    if (!lastLogin || !lastLogin.ok) return send(400, renderForm('<p class="bad">先登录再补抓。</p>'));
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const form2 = new URLSearchParams(Buffer.concat(chunks).toString('utf8'));
    const target = safeDecode((form2.get('url') || '').trim());
    if (!/^https?:\/\//i.test(target)) {
      return send(400, renderReport('<p class="bad">要填完整网址（http/https 开头）。</p>'));
    }
    console.log(`[manual] ${target}`);
    try {
      const r = await grabExtra(target, 'manual');
      writeReport();
      console.log(`[manual] ${r.status} ${r.file || r.note}`);
      res.writeHead(302, { Location: '/report' });
      return res.end();
    } catch (e) {
      return send(500, renderReport(`<p class="bad">抓取失败：${esc(e.message)}</p>`));
    }
  }

  send(404, page('404', '<h1>404</h1>'));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`学习通校准工具: http://127.0.0.1:${PORT}`);
  console.log(`产物目录: ${OUT}`);
  console.log('按 Ctrl+C 结束。');
});
