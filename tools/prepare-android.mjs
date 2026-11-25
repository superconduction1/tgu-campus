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
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import process from 'node:process';

const INTERNET_PERMISSION =
  '    <uses-permission android:name="android.permission.INTERNET"/>';
const CLEARTEXT_ATTR = 'android:usesCleartextTraffic="true"';
const APP_LABEL = '天工校园';
const MIN_SDK = 23;

/**
 * `flutter create .` 本意是「只补缺失的平台目录」，但这几个文件是我们自己写过的，
 * 一旦被模板覆盖，pubspec 的依赖、lint 排除规则、README 全没了——而且报错会
 * 出现在几百行 gradle 日志之后，很难联想到是这一步干的。
 * 所以生成前先备份到内存，生成后比对，变了就写回去。
 */
const PROTECTED_FILES = [
  'pubspec.yaml',
  'analysis_options.yaml',
  'README.md',
  '.gitignore',
  'lib/main.dart',
  'test/widget_test.dart',
];

/** 把可能要保护的文件读进内存（不存在的不记）。 */
function snapshotFiles(root, names) {
  const snapshot = new Map();
  for (const name of names) {
    const file = path.join(root, name);
    if (existsSync(file)) snapshot.set(name, readFileSync(file));
  }
  return snapshot;
}

/** 把被 create 改过/删掉的文件写回原内容，返回被动过的文件名。 */
function restoreClobbered(root, snapshot) {
  const restored = [];
  for (const [name, bytes] of snapshot) {
    const file = path.join(root, name);
    const same = existsSync(file) && readFileSync(file).equals(bytes);
    if (same) continue;
    writeFileSync(file, bytes);
    restored.push(name);
  }
  return restored;
}

/** 粗暴但够用的参数解析。 */
function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    patchOnly: false,
    selftest: false,
    org: 'edu.tgu',
    name: 'tgu_campus',
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--patch-only') out.patchOnly = true;
    else if (arg === '--selftest') out.selftest = true;
    else if (arg === '--root') out.root = argv[++i];
    else if (arg === '--org') out.org = argv[++i];
    else if (arg === '--project-name') out.name = argv[++i];
    else if (arg === '--help' || arg === '-h') {
      console.log('用法: node tools/prepare-android.mjs [--patch-only] [--root <dir>] [--org <id>] [--project-name <name>]');
      console.log('      node tools/prepare-android.mjs --selftest   # 只测「保护文件还原」，不碰项目');
      process.exit(0);
    } else {
      console.error(`不认识的参数: ${arg}`);
      process.exit(2);
    }
  }
  return out;
}

/** 自测：用临时目录模拟 flutter create 覆盖/删除受保护文件。 */
function selftest() {
  const dir = mkdtempSync(path.join(tmpdir(), 'tgu-prepare-'));
  let passed = 0;
  let failed = 0;
  const check = (name, actual, expected) => {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    console.log(
      `  ${ok ? 'PASS' : 'FAIL'}  ${name}` +
        (ok ? '' : `\n        期望 ${JSON.stringify(expected)}\n        实际 ${JSON.stringify(actual)}`),
    );
    if (ok) passed++;
    else failed++;
  };
  const write = (name, text) => writeFileSync(path.join(dir, name), text, 'utf8');
  const read = (name) => readFileSync(path.join(dir, name), 'utf8');

  try {
    write('pubspec.yaml', 'name: tgu_campus\ndependencies:\n  flutter_secure_storage: ^9.2.4\n');
    write('README.md', '# 天工校园\n');

    const snapshot = snapshotFiles(dir, PROTECTED_FILES);
    check('只备份确实存在的文件', [...snapshot.keys()].sort(), ['README.md', 'pubspec.yaml']);

    // 模拟 flutter create：覆盖 pubspec、删掉 README。
    write('pubspec.yaml', 'name: tgu_campus\n');
    rmSync(path.join(dir, 'README.md'));

    const restored = restoreClobbered(dir, snapshot);
    check('被改与被删的文件都还原', restored.sort(), ['README.md', 'pubspec.yaml']);
    check(
      'pubspec 内容一字不差',
      read('pubspec.yaml'),
      'name: tgu_campus\ndependencies:\n  flutter_secure_storage: ^9.2.4\n',
    );
    check('README 被删也能写回来', read('README.md'), '# 天工校园\n');
    check('已经一致时不重复写', restoreClobbered(dir, snapshot), []);
    check('没备份过的文件不会被凭空创建', existsSync(path.join(dir, 'analysis_options.yaml')), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  console.log(`\n自测：${passed} 通过，${failed} 失败\n`);
  process.exit(failed > 0 ? 1 : 0);
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
  if (args.selftest) selftest();
  const root = path.resolve(args.root);
  // 只在这个脚本真的要跑 flutter create 时才备份。
  const snapshot = existsSync(path.join(root, 'android'))
    ? new Map()
    : snapshotFiles(root, PROTECTED_FILES);
  const created = ensureScaffold(root, args.org, args.name, args.patchOnly);
  console.log(created ? '脚手架已生成\n' : 'android/ 已存在，跳过生成\n');

  if (created) {
    const restored = restoreClobbered(root, snapshot);
    if (restored.length > 0) {
      console.log(`flutter create 改动了 ${restored.length} 个文件，已还原：${restored.join('、')}\n`);
    }
  }

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
