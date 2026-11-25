#!/usr/bin/env node
// 一步准备好 android/ 目录：生成平台脚手架 + 打上必须的三处补丁。
//
// 为什么要脚本：`flutter create .` 生成的 Android 配置有两个坑
//   1. release manifest 里没有 INTERNET 权限 —— 装到手机上所有请求都失败，
//      表现为「网络错误」而不是崩溃，极难查；
//   2. minSdk 默认 21，而 flutter_secure_storage（Keystore）和
//      webview_flutter 4.x 都要 23。
// 手改容易漏，所以固化成脚本，本地和 CI 共用同一套。
//
// 用法：
//   node tools/prepare-android.mjs              # 生成（如果没有）+ 打补丁
//   node tools/prepare-android.mjs --patch-only # 只打补丁（android/ 已存在）
//   node tools/prepare-android.mjs --root <dir> # 指定项目根目录
//
// 幂等：重复跑不会重复插权限、不会把 minSdk 改坏。

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const INTERNET_PERMISSION =
  '    <uses-permission android:name="android.permission.INTERNET"/>';
const CLEARTEXT_ATTR = 'android:usesCleartextTraffic="true"';
const APP_LABEL = '天工校园';
const MIN_SDK = 23;

/** 粗暴但够用的参数解析。 */
function parseArgs(argv) {
  const out = { root: process.cwd(), patchOnly: false, org: 'edu.tgu', name: 'tgu_campus' };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--patch-only') out.patchOnly = true;
    else if (arg === '--root') out.root = argv[++i];
    else if (arg === '--org') out.org = argv[++i];
    else if (arg === '--project-name') out.name = argv[++i];
    else if (arg === '--help' || arg === '-h') {
      console.log('用法: node tools/prepare-android.mjs [--patch-only] [--root <dir>] [--org <id>] [--project-name <name>]');
      process.exit(0);
    } else {
      console.error(`不认识的参数: ${arg}`);
      process.exit(2);
    }
  }
  return out;
}

/** 没有 android/ 就调 flutter create 生成。返回是否真的生成过。 */
function ensureScaffold(root, org, name, patchOnly) {
  const androidDir = path.join(root, 'android');
  if (existsSync(androidDir)) return false;
  if (patchOnly) {
    console.error(`--patch-only 但 ${androidDir} 不存在`);
    process.exit(2);
  }
  console.log('android/ 不存在，先跑 flutter create …');
  execFileSync(
    'flutter',
    ['create', '.', '--platforms=android', '--org', org, '--project-name', name],
    { cwd: root, stdio: 'inherit', shell: true },
  );
  if (!existsSync(androidDir)) {
    console.error('flutter create 跑完了但 android/ 还是没有，检查 Flutter 安装');
    process.exit(2);
  }
  return true;
}

/**
 * 给 AndroidManifest.xml 补 INTERNET 权限和明文开关。
 * 两个补丁都按「找不到才插」处理，所以可以反复跑。
 */
function patchManifest(text) {
  const changes = [];
  let out = text;

  if (!out.includes('android.permission.INTERNET')) {
    const anchor = out.match(/<manifest[^>]*>\r?\n/);
    if (anchor) {
      out = out.replace(anchor[0], `${anchor[0]}${INTERNET_PERMISSION}\n`);
      changes.push('加 INTERNET 权限');
    } else {
      changes.push('!! 找不到 <manifest> 开标签，INTERNET 权限没加上');
    }
  }

  if (!out.includes('usesCleartextTraffic')) {
    // 属性必须落在 <application 的属性列表里，所以插在标签名之后。
    const opened = out.replace(/<application\b/, `<application\n        ${CLEARTEXT_ATTR}`);
    if (opened !== out) {
      out = opened;
      changes.push('加 usesCleartextTraffic');
    } else {
      changes.push('!! 找不到 <application> 标签，明文开关没加上');
    }
  }

  // 桌面图标下面的名字。模板默认是项目名（tgu_campus），中文名要自己补。
  if (!out.includes(`android:label="${APP_LABEL}"`)) {
    const existing = out.match(/android:label="[^"]*"/);
    if (existing) {
      out = out.replace(existing[0], `android:label="${APP_LABEL}"`);
      changes.push(`应用名 ${existing[0].slice('android:label='.length)} → "${APP_LABEL}"`);
    } else {
      const opened = out.replace(/<application\b/, `<application\n        android:label="${APP_LABEL}"`);
      if (opened !== out) {
        out = opened;
        changes.push(`加应用名 "${APP_LABEL}"`);
      } else {
        changes.push('!! 找不到 <application> 标签，应用名没改');
      }
    }
  }

  return { text: out, changes };
}

/**
 * 把 minSdk 调到 23。
 * 模板有几种写法：`minSdk 21`、`minSdk = 21`、`minSdk = flutter.minSdkVersion`。
 */
function patchGradle(text) {
  const changes = [];
  let out = text;

  const flutterDefault = /minSdk(\s*)=(\s*)flutter\.minSdkVersion/;
  // groovy 是 `minSdk 21`，kts 是 `minSdk = 21`，两种都要认。
  const numeric = /minSdk(?:Version)?(\s*)(=?)(\s*)(\d+)/;

  if (flutterDefault.test(out)) {
    out = out.replace(flutterDefault, `minSdk = ${MIN_SDK}`);
    changes.push(`minSdk: flutter.minSdkVersion → ${MIN_SDK}`);
  } else {
    const m = out.match(numeric);
    if (m && Number(m[4]) !== MIN_SDK) {
      const sep = m[2] === '=' ? ' = ' : ' ';
      out = out.replace(numeric, `minSdk${sep}${MIN_SDK}`);
      changes.push(`minSdk: ${m[4]} → ${MIN_SDK}`);
    } else if (!m) {
      changes.push('!! 找不到 minSdk，需要手动改成 23');
    }
  }

  return { text: out, changes };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const created = ensureScaffold(root, args.org, args.name, args.patchOnly);
  console.log(created ? '脚手架已生成\n' : 'android/ 已存在，跳过生成\n');

  const targets = [
    path.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    path.join(root, 'android', 'app', 'build.gradle'),
    path.join(root, 'android', 'app', 'build.gradle.kts'),
  ];

  let touched = 0;
  for (const file of targets) {
    if (!existsSync(file)) continue;
    const before = readFileSync(file, 'utf8');
    const isManifest = file.endsWith('AndroidManifest.xml');
    const { text, changes } = isManifest ? patchManifest(before) : patchGradle(before);
    if (changes.length === 0) {
      console.log(`${path.relative(root, file)}: 已符合要求`);
      continue;
    }
    if (text !== before) {
      writeFileSync(file, text, 'utf8');
      touched++;
    }
    console.log(`${path.relative(root, file)}:`);
    for (const c of changes) console.log(`  - ${c}`);
  }

  console.log(`\n完成，改了 ${touched} 个文件。`);
  console.log('下一步：flutter pub get && flutter build apk --debug');
}

main();
