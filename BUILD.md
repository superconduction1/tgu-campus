# 怎么在自己的手机上跑起来

仓库里已经有 `android/` 目录（本机生成并打过补丁），所以**不需要再装 Flutter 才能出包**，
但改代码后重新编译仍需要工具链。两条路：

- **路线 A：本机一条命令出包**（工具链已装好，约 3-5 分钟；推荐）
- **路线 B：GitHub Actions 打包**（不用动本机，但**产物下载很慢**，不推荐）

---

# 路线 A：本机一条命令出包（推荐）

工具链都在 `tgu_campus/.tools/` 下（已装好，不入库）：

| 组件 | 位置 | 版本 |
|---|---|---|
| Flutter SDK | `.tools/flutter` | 3.50.1 stable（自带 Dart 3.14.0） |
| JDK | `.tools/jdk/jdk-17.0.13+11` | 17.0.13 |
| Android SDK | `.tools/android-sdk`（platforms 34/35/36、build-tools 36.0.0、platform-tools） | — |
| NDK | `.tools/android-sdk/ndk/28.2.13676358` | r28c |

## 怎么跑

**双击仓库根目录的 `b.cmd`**（或在 cmd 里执行 `b.cmd`），
SmartScreen 弹「Windows 已保护你的电脑」时点「更多信息 → 仍要运行」。

它会：设好一整套环境变量（`HOME`/`APPDATA`/`GRADLE_USER_HOME`/`ANDROID_USER_HOME` 全部指到
`.home`，不污染真实用户目录）→ `flutter pub get` → `flutter build apk --debug`，
全程日志写到 `.tools/build.log`，结尾出现 `APK_OK` 就是成功。

产物：`build/app/outputs/flutter-apk/app-debug.apk`。

## 装到 MuMu 模拟器

```powershell
cd C:\Users\Q\Documents\deepseek-harness\default-workspace\tgu_campus
D:\MuMuPlayer\nx_main\adb.exe connect 127.0.0.1:16384
D:\MuMuPlayer\nx_main\adb.exe uninstall edu.tgu.tgu_campus   # 每次构建签名不同，必须卸载
D:\MuMuPlayer\nx_main\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
```

## 本机构建的已知坑（都已在 b.cmd 里处理好）

| 现象 | 原因 | 处理 |
|---|---|---|
| `flutter_tool_state` 写入失败 / `failed to list directory at "...\.home "` | `set VAR=value && ...` 把**尾随空格**写进了变量 | 一律用 `set "VAR=value"` |
| `AccessDeniedException ...\.android\debug.keystore.lock` | 用的是真实用户目录 | `ANDROID_USER_HOME` 指到 `.home\.android` |
| `CMake '3.22.1' was not found` | `path_provider_android 2.3.x` 走 `package:jni` 原生构建 | `pubspec.yaml` 里 `dependency_overrides: path_provider_android: 2.2.15` |
| `llvm-strip` 启动失败 / APK 1.4GB | `android/app/build.gradle.kts` 里没写 `ndkVersion`（AGP 会跳过 strip，符号全留）；或 `build/app/outputs/apk` 里有上一次 1.4GB 的旧产物，zipflinger 不会截断 | 1) 保留 `ndkVersion = "28.2.13676358"`；2) 构建前删掉 `build/app/outputs/apk` 与 `build/app/outputs/flutter-apk`。正常体积约 **68MB**（全 ABI）/ 约 40MB（`bx64.cmd` 单 x86_64） |
| `zip END header not found` | Gradle 发行包被下载器写坏 | 清空 `.home\.gradle\wrapper\dists\gradle-9.5.0-bin\*` 重下 |
| DSH 沙箱里 `flutter build` 报 `CreateFile failed 5` | 沙箱禁止子进程管道（git/flutter 都要起子进程） | 只能在**用户自己的窗口**里跑（b.cmd） |

> Gradle 走的是国内镜像：`mirrors.cloud.tencent.com` 的 `gradle-9.5.0-bin.zip`，
> Maven 走 `maven.aliyun.com`（`android/settings.gradle.kts` 与 `android/build.gradle.kts` 里排在官方源前面）。

---

# 路线 B：GitHub Actions（不推荐：下载很慢）

**这条路 76MB 的产物实测只有 0.04–0.06 MB/s，要 20–30 分钟**，除非本机工具链坏了，否则别用。

仍然保留它，是因为它同时做了三件事：`dart run bin/verify.dart`（270 项断言）、
`flutter analyze`、`flutter build apk --debug`。

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
