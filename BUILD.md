# 怎么在自己的手机上跑起来

仓库里只有 `lib/`（Dart 代码）和 `pubspec.yaml`，**没有 `android/` 目录** ——
生成平台目录必须有 Flutter SDK。两条路，选一条：

- **路线 A：GitHub Actions 打包**（不用装任何东西，推荐给只有手机/不想装 3GB 工具链的人）
- **路线 B：本机构建**（要装 Flutter + JDK + Android SDK，能热重载调试）

两条路都会跑同一个脚本 `tools/prepare-android.mjs`：它生成 `android/`，并打上三处必改的补丁。

---

# 路线 A：GitHub Actions（推荐）

本机不用装 Flutter / JDK / Android SDK，全部在 GitHub 的机器上跑完。

## 1. 建一个空仓库

浏览器打开 <https://github.com/new>，**不要**勾「Add a README / .gitignore / license」
（仓库必须完全空，否则推上去会冲突）。名字随便，比如 `tgu-campus`。

## 2. 把本地仓库推上去

仓库已经在本地初始化并提交好了（分支 `main`），远程地址也已经填好：

```
origin = https://github.com/superconduction1/tgu-campus.git
```

所以只有两件事要做：

```powershell
cd C:\Users\Q\Documents\deepseek-harness\default-workspace\tgu_campus

git push -u origin main
```

- 第一次 push 会弹浏览器让你登录 GitHub（Git 自带的凭据管理器，授权一次就行）。
- 如果第 1 步的仓库名不叫 `tgu-campus`，改一下地址：
  `git remote set-url origin https://github.com/superconduction1/你的仓库名.git`

### push 失败对照表

| 报错 | 真正的原因 | 怎么办 |
|---|---|---|
| `repository '...' not found` | 第 1 步的空仓库还没建出来（或仓库名不一样） | 回第 1 步建仓库，再核对 `git remote -v` 里的地址 |
| `remote origin already exists` | 之前加过一次 remote | 正常，说明地址已存在；直接 `git push -u origin main` |
| `Authentication failed` | 登录过期 | 控制面板 → 凭据管理器 → 删掉 `git:https://github.com`，重试 push |
| `src refspec main does not match any` | 本地分支名不是 `main` | `git branch -M main` 再来 |

> 想改提交里显示的名字/邮箱（现在是占位的 `tgu-campus`）：
> `git config user.name "你的名字"; git config user.email "你的GitHub邮箱"`
> 然后 `git commit --amend --reset-author --no-edit`。

## 3. 跑构建

推上去后 Actions **会自动开始跑一次**；没跑或失败了就手动触发：

1. 打开仓库 → **Actions** 标签 → 左边「构建 Debug APK」→ 右边 **Run workflow** → 绿色按钮。
2. 整个流程 5～10 分钟（第一次要下 Flutter SDK 和 Gradle，会慢一些）。
3. 成功后点进这次运行，页面底部 **Artifacts** 下载 `tgu-campus-debug-apk`，
   解压出 `app-debug.apk`。
4. 传到手机安装（要允许「安装未知来源应用」）。

工作流 `.github/workflows/android-debug.yml` 一共 12 步，关键几步红了就停：

| 步骤 | 挂了说明什么 |
|---|---|
| 补丁脚本自测 | `tools/prepare-android.mjs` 的还原逻辑坏了（模拟 `flutter create` 覆盖文件后能否还原） |
| 准备 Android 工程 | `flutter create` 出问题，或补丁脚本没找到文件（日志里会打印 `!!`） |
| 断言集 | 解析器 / 加密 / 时间规则的 221 项断言里有失败，日志会打印哪一条 |
| 静态检查 | `flutter analyze` 有 error（info 不算） |
| 单元测试（不阻塞） | 这一步失败**不影响出包**，但日志里会写哪个 test 挂了 → 发我 |
| 构建 APK | Gradle / 依赖问题，看日志里第一个 `FAILURE:` |

> Debug 包用调试签名，能装机自用；别上架、别分发给不特定的人。

---

# 路线 B：本机构建

## 0. 装 Flutter

- 需要 **Flutter 3.24 或更高**（对应 Dart 3.5+）。装完 `flutter --version` 确认。
- 国内网络建议先设两个镜像（只对当前终端有效）：

  ```powershell
  $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
  $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
  ```

- 还要有 JDK 17、Android SDK 和一台开了 USB 调试的手机，`flutter doctor` 里 Android 那几项打勾。

## 1. 生成 android/ 并打补丁（一步）

```powershell
cd tgu_campus
node tools/prepare-android.mjs
```

它等价于下面这些手工操作，**幂等**，重复跑不会重复插权限：

1. `flutter create . --platforms=android --org edu.tgu --project-name tgu_campus`
   （只补 `android/`，不覆盖 `lib/`、`pubspec.yaml`）；
2. `android/app/src/main/AndroidManifest.xml` 加
   `<uses-permission android:name="android.permission.INTERNET"/>` —— **`flutter create`
   只给 debug/profile 的 manifest 带这条，release 包不加就所有请求失败**，
   表现为「网络错误」而不是崩溃，极难查；
3. 同一个 manifest 的 `<application>` 上加 `android:usesCleartextTraffic="true"`
   —— 教务登录后有一次 302 会指向 `http://`；
4. `android/app/build.gradle(.kts)` 的 `minSdk` 调到 **23** —— 默认 21，而
   `flutter_secure_storage` 的 EncryptedSharedPreferences 要 23，
   `webview_flutter` 4.x 也要 23。

跑完会打印改了哪几行。手动改也行，逻辑就在那个脚本里，照抄即可。

## 2. 座位预约页的额外要求

`webview_flutter` 用的是手机自带的 Android System WebView，国内机型上如果版本太老，
页面可能白屏；真遇到就在应用商店更新「Android System WebView」。

## 3. 拉依赖 + 静态检查

```powershell
flutter pub get
flutter analyze
```

lint 建议（`prefer_const_constructors`、`use_super_parameters` 之类）可以不管，
**只有 error 需要停下来**。

## 4. 跑起来 / 打包

```powershell
flutter run -d <device-id>        # 调试，支持热重载
flutter build apk --debug         # 产物：build/app/outputs/flutter-apk/app-debug.apk
```

侧载自用足够，手机端开「允许安装未知来源的应用」，`adb install` 或直接拷过去点安装。

## 5. 第一次启动会看到什么

1. 启动闸门先查有没有存过 Cookie：有就探活，直接进首页；没有就回登录页。
2. 登录页：学号 + 密码 + 验证码（验证码图 180×60，点一下换一张）。
3. 首页：顶部「今天 · 周X」今日课程卡，下面是模块格子 —— 课表 / 成绩 / 考试 / 待办 /
   作业 / 座位预约。
4. 点「作业」或「座位预约」时第一次会让你**单独**登一次学习通
   （两个系统的会话分开存，互不影响）。座位预约还要粘一次地址，见页内三步说明。

## 6. 已知会踩的坑

| 现象 | 原因 / 处理 |
|---|---|
| Gradle 下载卡住 | 换阿里/腾讯 Gradle 镜像，或先跑 `flutter doctor --android-licenses` |
| 第一次读写存储略慢 | `flutter_secure_storage` 初始化 Keystore，不是卡死 |
| 页面显示「教务登录已过期」 | 点那个页面上的「重新登录」，学号会预填，不用自己找退出入口 |
| NDK 版本 warning | 可忽略，不影响构建 |
| 学习通作业提示「无效的用户」 | 作业 URL 少了 `t`/`stuenc` 参数，是解析器的问题，不是账号问题 |
| 座位页白屏 | 系统 WebView 太老，去应用商店更新「Android System WebView」 |

## 7. 我这边已经验证到哪一层

工具链不齐（沙箱不让工具 spawn 子进程），但该验的都验了：

- `tools/verify/bin/verify.dart`：**214 项断言**，纯 Dart，覆盖密码变换、AES、
  HTML 表格提取、课表解析与周次过滤、成绩统计、学期条、编码嗅探、
  学习通课程/作业解析、座位时间规则与 Cookie 域推导（含真实抓包回归），
  外加把 `dump/` + `dump-cx/` 的 **158 个真实页面**全过一遍解析器，确认零异常。
- `tools/verify/bin/syntax.dart`：`lib/` 全部 **31 个文件** 语法检查。
- `tools/verify/bin/resolve.dart`：**真类型检查**（analyzer 在进程内解析，
  连 `package:flutter` 一起），`lib/` + `test/` 共 **36 个文件** 0 error / 0 warning。
- `frontend_server` 把整个 App 编成 kernel，**退出码 0**（约 61 MB），
  相当于 `flutter build apk` 的 Dart 阶段。

还没做过的只有「真机跑起来」这一步，以及 Gradle 那一侧（要 JDK + Android SDK）。
