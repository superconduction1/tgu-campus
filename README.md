# 天工校园 · TGU Campus

天津工业大学校园聚合 App（单人自用，Android 侧载）。把 URP 教务、学习通作业、
图书馆座位预约收到一个界面里。

---

## 现在到哪一步了

**登录链路已完全打通，并且是对着真实服务器验证过的。**

| 项 | 状态 | 依据 |
|---|---|---|
| 教务登录页结构 | ✅ 已逆出 | 实测 `GET /login` |
| 密码变换算法 | ✅ 已逆出并写单测 | 逐字还原 `md5.min.js` |
| 验证码获取 | ✅ 已通 | 实测返回 180×60 JPEG |
| 登录请求字段 | ✅ 已验证 | 服务端回 `badCaptcha` 而非 400/500，说明字段全对 |
| 免登录（Cookie 复用） | ⏳ 待真实账号验证 | 代码已就绪 |
| 课表：数据接口 | ✅ 已打通 | 真实数据 14 门课 / 26.75 学分 |
| 课表：周网格界面 | ✅ 已实现 | 排版逻辑有 12 项测试 |
| 学期 / 当前周次 | ✅ 已打通 | 首页 `span_bbzx`，实测第 13 周，不用抓校历 |
| 首页·今日课程 | ✅ 已实现 | 复用周次过滤，真实数据：第13周周三 08:20 高数、16:00 军事理论 |
| 成绩：接口 | ✅ 已打通 | 当前空（大一第一学期，尚无已结束课程） |
| 成绩：解析器 | ✅ 已实现 | 表格版 + JSON 版，构造数据验证 |
| 考试安排 | ⏳ 页面已通，无数据 | 服务端渲染，有考试时表格自动出现 |
| 待办 | ✅ 已实现（当前为空） | 聚合学分确认 + 学业预警，实测都返回「没有」 |
| 学习通作业 | ✅ 能取列表（当前无作业） | 公式 `&enc=<workEnc>&t=<t>&stuenc=<enc>` 实测拿到 `<title>作业列表</title>`；两门课都是「暂无作业」，条目 DOM 等有作业时再校准 |
| 座位预约 | ✅ 可用了（自带 WebView） | 机构应用只挂在学习通 App 里，地址让用户粘一次（也支持「先打开学习通」+「粘贴剪贴板地址」两条兜底）；打开时自动注入学习通登录 Cookie（免二次登录）；页面内置 22:00 开放倒计时，不代签到 |
| 会话过期 | ✅ 不再卡死 | 教务登录过期时给「重新登录」按钮：清凭据 → 回登录页（学号预填），不用自己找退出入口 |
| 编译验证 | ✅ 真编过 | 类型检查 30 文件 0 错；`frontend_server` 编成 kernel 退出码 0 |

**想装上手机 → [BUILD.md](BUILD.md)**，两条路：

- **不想装工具链**：推到 GitHub，在 Actions 里点一下「构建 Debug APK」，
  下 Artifacts 里的 `app-debug.apk` 直接装（工作流已写好）。
- **本机构建**：`node tools/prepare-android.mjs` 一步生成 `android/`
  并补上 INTERNET 权限、明文开关、minSdk 23（这三处是装到手机上必踩的坑）。

关键结论：教务是 **清元优软 URP + Spring Security**，密码不是明文也不是普通
MD5，而是：

```
j_password = MD5( MD5(pwd + "{Urp602019}") ) + "*" + MD5( MD5(pwd) )
```

左右两半**不对称**（右边少一次加盐）。这是整个登录里最容易写错的一步，
`lib/core/urp_crypto.dart` 里已按原样实现并有测试向量。

---

## 学习通校准：再跑一轮（工具已升级）

第一轮跑完了（`dump-cx/` 里 46 个文件），结论有两条：

1. **登录通了**，首页、课程、知识点都抓到了，但 45 个页面**没有一个是 JSON / 作业列表**——
   学习通的列表是服务端渲染或原生页面，盲目点链接抓不到。
2. 从课程页里挖到了作业列表的真实地址：
   `<a title="作业" data-url="https://mooc1.chaoxing.com/mooc2/work/list">`，
   参数是该页自己的 `courseId` / `clazzId` / `cpi`。这条路是确定的。

所以工具改成了「点名抓」：

```bash
node tools/spike-cx.mjs        # 浏览器开 http://127.0.0.1:8788，输学习通手机号+密码
```

登录后会做三件事：

- 常规抓取（从登录返回地址出发，最多 60 个链接，跳过登出）
- **第二轮**：从抓到的页面里凑出每门课的 `courseId / classId / cpi`，
  逐门直接请求 `mooc1.chaoxing.com/mooc2/work/list?...`，存成 `x??_work_*.html`
- 报告页底部有个**「再抓一个网址」**输入框：把手机上「座位预约」那个页面的地址粘进去，
  它就会带着你的登录态去抓一次，存成 `x??_manual_*.html`

座位预约目前**没有任何外链**——图书馆官网只写「在学习通里点座位预约」，
`tsgseat / seat / libseat .chaoxing.com` 这些域名都不存在。
所以座位这一块要靠你提供一次地址：在学习通里打开「座位预约」，把地址栏的链接抄给我
（实在找不到就抓包，或者先跳过，作业那块不依赖它）。

把 `dump-cx/` 整个发我。

> 安全：工具只在本地跑，账号密码只在内存里用一次，不写盘、不上传、不打印。
> 抓完关掉进程即全部丢弃。

教务的 `tools/spike.mjs` 还留着，以后要补「教务待办」「校历」时再跑一次就行。

---

## 工程结构

```
lib/
  core/
    config.dart        # 学校各系统入口常量 + UrpPaths 路径表（全部实测得来）
    urp_crypto.dart    # URP 密码变换（有单测）
    chaoxing_crypto.dart # 学习通 AES-128-CBC（key==IV）
    http.dart          # Cookie 感知的 HTTP 客户端，手动处理 302
    html_table.dart    # 通用表格提取（rowspan/colspan/嵌套表）
    session.dart       # 凭据存储（Android Keystore，不落明文）
  features/
    urp/urp_api.dart       # 登录、验证码、AJAX callback 地址提取
    urp/urp_parser.dart    # 成绩/考试（按列名找列，不依赖 DOM 路径）
    urp/models.dart        # 课表/成绩/考试数据模型
    urp/timetable_grid.dart # 周网格排版（纯 Dart，可测）
    urp/timetable_page.dart # 课表界面
    chaoxing/cx_api.dart   # 学习通登录 + 课程/作业抓取
    chaoxing/cx_parser.dart     # 课程列表、隐藏域、作业列表解析
    chaoxing/homework_page.dart # 作业页（未登录时内嵌学习通登录）
    chaoxing/seat_rules.dart    # 22:00 开放规则 + 地址校验（纯 Dart，可测）
    chaoxing/seat_store.dart    # 座位入口地址的本地存储
    chaoxing/seat_page.dart     # 座位页（WebView 承载 + 开放倒计时）
    login/                 # 登录页
    home/                  # 九宫格首页 + 诊断导出
    diagnostics/           # 原始页面转储
tools/
  spike.mjs            # 教务校准工具（8787），不进 APK
  spike-cx.mjs         # 学习通校准工具（8788），不进 APK
  prepare-android.mjs  # 生成 android/ 并打上必须的三处补丁，本地与 CI 共用
  verify/              # 不依赖 Flutter 的验证脚手架（断言 / 语法 / 类型）
test/
  urp_crypto_test.dart # 密码变换向量
  cookie_jar_test.dart # Cookie 行为
```

两个设计决定：

1. **不用 dio。** 登录失败是 `302 -> /login?errorCode=xxx`，必须看得见
   `Location` 才能区分"验证码错"和"成功"。自动跟随重定向会把这信息吃掉。
2. **凭据不进后端。** 单人自用没有理由架服务器；密码只在本机 Keystore。

---

## 本地验证

`lib/core` 与 `lib/features/urp` 是不依赖 Flutter 的纯 Dart，可以单独编译并跑断言：

```bash
cd tools/verify
dart pub get
dart run bin/verify.dart    # 逻辑断言
dart run bin/syntax.dart    # 全量语法检查
dart run bin/resolve.dart   # 全量类型检查（需要 FLUTTER_ROOT）
```

- `verify.dart`：URP 密码变换、学习通 AES、CookieJar、HTML 表格提取（含 rowspan）、
  成绩解析（表格版和 AJAX JSON 版）、课表 JSON、网格布局、接口提取，
  以及**用 dump 里的真实响应做的回归**，最后还会把 `dump/`+`dump-cx/` 里
  **全部 158 个真实页面**过一遍所有解析器，确保任何一页都不会把解析器搞崩。**当前 214 项通过 / 0 失败。**
- `syntax.dart`：用 analyzer 的纯语法解析检查 `lib/` 下每个文件。
  不需要 Flutter SDK，所以连界面代码也能查。**当前 30 个文件全部通过。**
- `resolve.dart`：**真类型检查**。用 analyzer 的 `AnalysisContextCollection` 在
  本进程内做完整解析（把 `package:flutter` 一起解析进来），能抓出方法不存在、
  参数类型不匹配、构造函数缺参数这类语法检查看不见的错。
  需要 `FLUTTER_ROOT` 指向 Flutter SDK：

  ```powershell
  $env:FLUTTER_ROOT = "<项目>\.tools\flutter"   # 或本机任意 Flutter 安装
  dart run bin/resolve.dart
  ```

  **当前 30 个文件 0 error / 0 warning。**（它抓出的第一个真 bug：
  `lib/features/diagnostics/diagnostics.dart` 的 `../core/` 少一层，应为 `../../core/`。）

- 还有一步「真编译」：用 Flutter 自带的 `frontend_server` 把整个 App 编成 kernel，
  连 `package:flutter` 一起编，等于 `flutter build apk` 的 Dart 阶段。已验证通过：

  ```powershell
  $f = "<项目>\.tools\flutter"; $eng = "$f\bin\cache\artifacts\engine"
  & "$f\bin\cache\dart-sdk\bin\dartaotruntime.exe" `
    "$eng\windows-x64\frontend_server_aot.dart.snapshot" `
    --sdk-root "$eng\common\flutter_patched_sdk/" --target=flutter `
    --packages "<项目>\.dart_tool\package_config.json" `
    --output-dill "<项目>\.tools\app.dill" "<项目>\lib\main.dart"
  ```

  产物约 61 MB、退出码 0。**注意**：这一步只证明 Dart 侧能编过；出 APK 还差
  Android SDK + JDK（见 `BUILD.md`）。

前两步不是形式主义，它们抓出过四个真 bug：`HttpHeaders.set` 返回 `void` 却用了级联、
`urp_api.dart` 的相对路径少了一层、`headers` 参数遮蔽局部变量、
`extractCallbackUrl` 的正则把 `=` 后的空格弄丢了。

> 为什么不用 `flutter analyze`：它会 spawn 一个 `analysis_server` 子进程，而这台
> 机器上的沙箱不允许子进程用管道捕获输出（`ProcessException: 拒绝访问`）。
> `resolve.dart` 把同一套分析器库放进本进程跑，效果等价、不依赖子进程。
> 在你自己电脑上，`flutter analyze` 当然更省事。

## 构建（可选，装 Flutter 后）

```bash
flutter create --platforms=android --org cn.tgu .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Flutter 走国内镜像会快一些：

```powershell
$env:PUB_HOSTED_URL   = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
```

---

## 边界（写清楚，免得后面返工）

- **不自动签到**：图书馆签到是「扫座位二维码 + GPS 定位」双重校验，
  自动化等于伪造位置绕开违约规则。
- **不代做作业**：只读，不提交。
- **不上架应用商店**：无授权，涉及第三方接口与商标。
- 座位预约每天最多取消 3 次、每周违约 3 次停用，UI 上要做二次确认。

---

## 下一步

1. 跑 `tools/spike.mjs`，把 `dump/` 发我
2. 我写 URP 四个模块的解析器
3. 同样方式校准学习通（作业 + 座位预约）
4. UI 收尾、打包
