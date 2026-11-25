#!/usr/bin/env node
/**
 * URP 校准工具（一次性使用，不参与最终 App）
 *
 * 作用：用你自己的账号登录教务系统，把登录后的真实页面全部抓下来存成文件。
 * 为什么需要它：解析器只能对着真实 DOM 写，猜结构等于白写。
 *
 * 用法：
 *   1. 在项目根目录执行：node tools/spike.mjs
 *   2. 浏览器会自动打开 http://127.0.0.1:8787
 *   3. 输入学号、密码、验证码，点登录
 *   4. 成功后把打印出来的 dump 目录发给我
 *
 * 安全：账号密码只在内存里用一次，不写盘、不上传、不打印。
 *      抓完页面后进程退出即全部丢弃。
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { exec } from 'node:child_process';

const HOST = 'jwxs.tiangong.edu.cn';
const BASE = `https://${HOST}`;
const PORT = Number(process.env.SPIKE_PORT || 8787);
const DUMP_DIR = path.resolve('dump');
const SALT = '{Urp602019}';
const MAX_PAGES = 60;

// 绝对不能抓的链接：首页上有「退出系统」，抓一次就把自己的会话登出了，
// 后面所有 /student/... 都会 302 到 gotoLogin（实测踩过这个坑）。
const SKIP_PATTERN = /logout|enterOut|gotoLogin|signout|signOut|exit/i;

/* ----------------------------- Cookie jar ----------------------------- */

let jar = [];

const cookieHeader = () => jar.map((c) => c.split(';')[0]).join('; ');

function absorb(res) {
  for (const raw of res.headers.getSetCookie()) {
    const pair = raw.split(';')[0];
    const name = pair.split('=')[0];
    jar = jar.filter((x) => x.split('=')[0] !== name);
    jar.push(pair);
  }
}

/* ------------------------------ 密码变换 ------------------------------ */

const md5Hex = (s) =>
  crypto.createHash('md5').update(Buffer.from(s, 'utf8')).digest('hex');

// 等价于 jwxs 的 hex_md5(s, ver)：ver === '1.8' 时不加盐
const hexMd5 = (s, withSalt) => md5Hex(withSalt ? s + SALT : s);

function transformPassword(pwd) {
  const left = hexMd5(hexMd5(pwd, true), false);
  const right = hexMd5(hexMd5(pwd, false), false);
  return `${left}*${right}`;
}

// 启动自检：口算向量对不上就别往下跑了。
const EXPECTED = 'ca1b3db944006232ca6c5f3e8137c271*14e1b600b1fd579f47433b88e8d85291';
if (transformPassword('123456') !== EXPECTED) {
  console.error('URP 密码变换自检失败，停止。');
  process.exit(1);
}

// 学习通 AES 也顺手自检一下（同一套算法也在 App 里实现）。
const CX_KEY = 'u2oh6Vu^HWe4_AES';
const cxEncrypt = (m) => {
  const c = crypto.createCipheriv(
    'aes-128-cbc',
    Buffer.from(CX_KEY, 'utf8'),
    Buffer.from(CX_KEY, 'utf8')
  );
  return Buffer.concat([c.update(Buffer.from(m, 'utf8')), c.final()]).toString('base64');
};
if (cxEncrypt('13800138000') !== 'yYcVatS+4J+JGnm88UM56A==') {
  console.error('学习通 AES 自检失败，停止。');
  process.exit(1);
}

/* ------------------------------ 登录流程 ------------------------------ */

let state = { token: null, captcha: null, error: null, done: null };

async function loadTicket() {
  const res = await fetch(`${BASE}/login`);
  absorb(res);
  const html = await res.text();
  const m = html.match(/id="tokenValue"[^>]*value="([^"]+)"/);
  state.token = m ? m[1] : null;

  const cap = await fetch(`${BASE}/img/captcha.jpg`, {
    headers: { cookie: cookieHeader() },
  });
  absorb(cap);
  state.captcha = Buffer.from(await cap.arrayBuffer());
}

async function doLogin(username, password, captcha) {
  const body = new URLSearchParams({
    lang: 'zh',
    tokenValue: state.token ?? '',
    j_username: username,
    j_password: transformPassword(password),
    j_captcha: captcha,
  });

  const res = await fetch(`${BASE}/j_spring_security_check`, {
    method: 'POST',
    redirect: 'manual',
    headers: {
      cookie: cookieHeader(),
      'content-type': 'application/x-www-form-urlencoded',
      referer: `${BASE}/login`,
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0.0.0',
    },
    body,
  });
  absorb(res);

  const location = res.headers.get('location') ?? '';
  console.log(`  登录响应 ${res.status} -> ${location || '(无 Location)'}`);
  console.log(`  会话 Cookie: ${jar.map((c) => c.split('=')[0]).join(', ')}`);

  const code = location.match(/errorCode=([A-Za-z0-9_]+)/);
  if (code) return { ok: false, code: code[1] };

  // 吞掉响应体，保持连接干净
  await res.text();
  return { ok: true };
}

/* ------------------------------- 抓页面 ------------------------------- */

/// 登录后先探一个学生页，确认会话真的建立了。
/// 塞了几十个 302 的 dump 对排查毫无帮助，不如早报错。
async function probeSession() {
  const url = `${BASE}/student/integratedQuery/scoreQuery/allPassingScores/index`;
  const res = await fetch(url, {
    headers: { cookie: cookieHeader(), referer: BASE },
    redirect: 'manual',
  });
  absorb(res);
  const location = res.headers.get('location') ?? '';
  return {
    ok: res.status === 200 && !/gotoLogin|errorCode/.test(location),
    status: res.status,
    location,
  };
}

function sanitize(url) {
  const u = new URL(url, BASE);
  let p = `${u.pathname}${u.search}`.replace(/[^A-Za-z0-9._-]/g, '_');
  p = p.replace(/_+/g, '_').replace(/^_/, '');
  return p.slice(0, 80) || 'root';
}

function extractLinks(html, baseUrl) {
  const out = new Set();
  const re = /<a\b[^>]*href=["']([^"']+)["']/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const raw = m[1].trim();
    if (!raw || raw.startsWith('#') || raw.startsWith('javascript:')) continue;
    if (raw.startsWith('mailto:') || raw.startsWith('tel:')) continue;
    try {
      const abs = new URL(raw, baseUrl);
      if (abs.host !== HOST) continue;
      if (SKIP_PATTERN.test(abs.pathname)) continue;
      if (/\.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?)$/i.test(abs.pathname)) continue;
      out.add(`${abs.origin}${abs.pathname}${abs.search}`);
    } catch {
      /* ignore */
    }
  }
  return [...out];
}

/// 页面里内联的 AJAX 端点，就是真正返回数据的地址。
/// URP 的路径里常带一段随机字符（如 /8U5kzu4lLM/），只能从页面上读。
function extractCallbackUrls(html) {
  const out = new Set();
  const patterns = [
    /var\s+url\s*=\s*["']([^"']+)["']/g,
    /\$\.get\(\s*["']([^"']+)["']/g,
    /url\s*:\s*["']([^"']+)["']/g,
  ];
  for (const re of patterns) {
    for (const m of html.matchAll(re)) {
      const u = m[1];
      if (!u.startsWith('/')) continue;
      if (/\.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?)$/i.test(u)) continue;
      if (/\/index$/.test(u)) continue; // 整页地址，不是接口
      out.add(u);
    }
  }
  return [...out];
}

async function crawl(startUrls) {
  fs.rmSync(DUMP_DIR, { recursive: true, force: true });
  fs.mkdirSync(DUMP_DIR, { recursive: true });

  const queue = [...startUrls];
  const seen = new Set();
  const callbackUrls = [];
  const apiSeen = new Set();
  const index = [];
  let n = 0;

  while (queue.length > 0 && n < MAX_PAGES) {
    const url = queue.shift();
    if (seen.has(url)) continue;
    seen.add(url);
    if (SKIP_PATTERN.test(new URL(url).pathname)) {
      index.push(`SKIP       ${url}  (登出类链接，抓了会掉线)`);
      continue;
    }

    try {
      const res = await fetch(url, {
        headers: {
          cookie: cookieHeader(),
          referer: BASE,
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0.0.0',
        },
        redirect: 'manual',
      });
      absorb(res);

      const location = res.headers.get('location') ?? '';
      const type = res.headers.get('content-type') ?? '';
      const html = type.includes('text/html') ? await res.text() : '';

      n += 1;
      const file = `${String(n).padStart(2, '0')}_${sanitize(url)}.html`;
      if (html) fs.writeFileSync(path.join(DUMP_DIR, file), html, 'utf8');

      index.push(
        `${String(res.status).padEnd(4)} ${String(html.length).padStart(7)}B  ${url}` +
          (location ? `  -> ${location}` : '') +
          (html ? `  => ${file}` : '')
      );

      // 页面里内联的 AJAX 端点往往就是拿真实数据的地方，顺手记下来
      if (html) {
        const ajax = [
          ...new Set(
            [...html.matchAll(/url\s*:\s*['"]([^'"]{2,120})['"]/g)].map((m) => m[1])
          ),
        ];
        if (ajax.length > 0) {
          index.push(`     AJAX: ${ajax.slice(0, 12).join(' | ')}`);
        }
      }

      if (html && res.status === 200) {
        for (const link of extractLinks(html, url)) {
          if (!seen.has(link) && queue.length + n < MAX_PAGES * 2) queue.push(link);
        }
        for (const api of extractCallbackUrls(html)) {
          if (!apiSeen.has(api)) {
            apiSeen.add(api);
            callbackUrls.push(api);
          }
        }
      }
    } catch (err) {
      index.push(`ERR  ${url}  ${err.message}`);
    }
  }

  // 跟进页面里的 AJAX 端点，把真正的 JSON 存下来
  let apiCount = 0;
  for (const api of callbackUrls) {
    apiCount += 1;
    const abs = api.startsWith('http') ? api : BASE + api;
    try {
      const res = await fetch(abs, {
        headers: {
          cookie: cookieHeader(),
          referer: BASE,
          'x-requested-with': 'XMLHttpRequest',
        },
        redirect: 'manual',
      });
      absorb(res);
      const type = (res.headers.get('content-type') || '').split(';')[0];
      const text = await res.text();
      const name = `api_${String(apiCount).padStart(2, '0')}_${sanitize(api)}.json`;
      fs.writeFileSync(path.join(DUMP_DIR, name), text, 'utf8');
      index.push(
        `API  ${String(res.status).padEnd(3)} ${String(text.length).padStart(7)}B  ${abs}  ${type}  => ${name}`
      );
    } catch (err) {
      index.push(`API  ERR ${abs}  ${err.message}`);
    }
  }

  fs.writeFileSync(path.join(DUMP_DIR, 'index.txt'), index.join('\n'), 'utf8');
  return index;
}

/* ------------------------------- Web UI ------------------------------- */

const page = (inner) => `<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>URP 校准</title>
<style>
  body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#71246b;
       min-height:100vh;margin:0;display:flex;align-items:center;justify-content:center}
  .card{background:#fff;border-radius:14px;padding:28px;width:min(92vw,400px);
        box-shadow:0 18px 50px rgba(0,0,0,.28)}
  h1{font-size:17px;margin:0 0 4px;color:#71246b}
  p.sub{font-size:12px;color:#888;margin:0 0 18px}
  label{display:block;font-size:12px;color:#666;margin:12px 0 4px}
  input{width:100%;box-sizing:border-box;padding:10px;border:1px solid #ddd;
        border-radius:8px;font-size:15px}
  .row{display:flex;gap:10px;align-items:flex-end}
  .row input{flex:1}
  img{height:46px;width:138px;object-fit:contain;border:1px solid #eee;border-radius:6px;
      cursor:pointer;background:#fafafa}
  button{margin-top:18px;width:100%;padding:13px;border:0;border-radius:9px;
         background:#71246b;color:#fff;font-size:15px;cursor:pointer}
  .err{background:#fdecea;color:#a02c22;padding:9px 11px;border-radius:7px;
       font-size:13px;margin-top:14px}
  pre{background:#f6f6f8;padding:12px;border-radius:8px;font-size:11px;
      max-height:320px;overflow:auto;white-space:pre-wrap}
  code{background:#f0f0f4;padding:1px 5px;border-radius:4px;font-size:12px}
</style></head><body><div class="card">${inner}</div></body></html>`;

const loginForm = (error) => page(`
  <h1>URP 校准</h1>
  <p class="sub">只在本地运行 · 凭据不落盘 · 抓完即丢</p>
  <form method="post" action="/login">
    <label>学号</label>
    <input name="username" autocomplete="off" required>
    <label>密码</label>
    <input name="password" type="password" required>
    <label>验证码</label>
    <div class="row">
      <input name="captcha" maxlength="4" required>
      <img src="/captcha.png?${Date.now()}" onclick="this.src='/captcha.png?'+Date.now()" alt="点击刷新">
    </div>
    <button>登录并抓取</button>
  </form>
  ${error ? `<div class="err">${error}</div>` : ''}
  <p class="sub" style="margin-top:16px">点验证码可以换一张。</p>`);

const doneView = (index) => page(`
  <h1>抓取完成</h1>
  <p class="sub">把下面这个目录整个发给我：</p>
  <p><code>${DUMP_DIR}</code></p>
  <pre>${index.join('\n')}</pre>`);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${PORT}`);

  try {
    if (url.pathname === '/captcha.png') {
      if (!state.captcha) await loadTicket();
      res.writeHead(200, { 'content-type': 'image/jpeg', 'cache-control': 'no-store' });
      res.end(state.captcha);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/login') {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      const form = new URLSearchParams(raw);
      const user = (form.get('username') ?? '').trim();
      const pwd = form.get('password') ?? '';
      const cap = (form.get('captcha') ?? '').trim();

      if (!state.token) await loadTicket();
      const result = await doLogin(user, pwd, cap);

      if (!result.ok) {
        await loadTicket();
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        res.end(
          loginForm(
            result.code === 'badCaptcha'
              ? '验证码错误，已换一张，请重试。'
              : `登录失败：${result.code}`
          )
        );
        return;
      }

      console.log('  正在确认会话…');
      const probe = await probeSession();
      if (!probe.ok) {
        console.log(
          `  ✗ 会话没建立：status=${probe.status} location=${probe.location || '-'}`
        );
        console.log('    未开始抓取（避免再产出一堆 302）。');
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        res.end(
          page(`
          <h1>登录成功，但会话没建立</h1>
          <p class="sub">探测学生页返回：</p>
          <pre>status = ${probe.status}
location = ${probe.location || '(空)'}</pre>
          <p class="sub">把这行信息发给我，我来判断是 Cookie 没带全还是要跟一次跳转。</p>`)
        );
        return;
      }
      console.log('  ✓ 会话正常，开始抓取');

      const seeds = [
        '/',
        '/index.jsp',
        // 这些是从首页菜单里扒出来的真实学生端入口（已确认路径有效）
        '/student/integratedQuery/scoreQuery/allPassingScores/index',
        '/student/integratedQuery/scoreQuery/thisTermScores/index',
        '/student/integratedQuery/scoreQuery/unpassedScores/index',
        '/student/courseSelect/thisSemesterCurriculum/index',
        '/student/examinationManagement/examPlan/index',
        '/student/examinationManagement/examGrade/index',
        '/student/teachingResources/freeClassroom/index',
        '/student/personalManagement/warningInfo/queryWarningInfo',
        '/student/application/index',
      ].map((p) => BASE + p);
      const index = await crawl(seeds);
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(doneView(index));
      return;
    }

    if (!state.token) await loadTicket();
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(loginForm(null));
  } catch (err) {
    res.writeHead(500, { 'content-type': 'text/html; charset=utf-8' });
    res.end(page(`<h1>出错了</h1><pre>${String(err && err.stack)}</pre>`));
  }
});

server.listen(PORT, '127.0.0.1', () => {
  const target = `http://127.0.0.1:${PORT}`;
  console.log(`\n  校准工具已启动：${target}\n`);
  console.log(`  抓取结果会存到：${DUMP_DIR}\n`);
  if (!process.env.SPIKE_NO_BROWSER) exec(`start "" "${target}"`, () => {});
});
