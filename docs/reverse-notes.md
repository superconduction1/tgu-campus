# 逆向笔记：学校各系统的真实接口

> 这些结论全部来自实际请求，不是从别的项目抄的。换学校的话基本要全部重来，
> 但方法一样。

---

## 1. URP 教务（jwxs.tiangong.edu.cn）

### 登录链路

| 步骤 | 请求 | 说明 |
|---|---|---|
| 1 | `GET /login` | 下发 `student.urpSoft.cn`、`route`；页面里有隐藏字段 `tokenValue`（32 位 hex） |
| 2 | `GET /img/captcha.jpg` | 180×60 JPEG，4 位字符；**`JSESSIONID` 在这一步才建立** |
| 3 | `POST /j_spring_security_check` | 表单字段见下 |

表单字段：

```
lang=zh
tokenValue=<从登录页抓>
j_username=<学号>
j_password=<见下方变换>
j_captcha=<4 位验证码>
```

### 密码变换（关键）

`js/md5/md5.min.js` 里的 `hex_md5(string, ver)` 不是普通 MD5：

```js
string = md5_Utf8Encode(string + (ver === "1.8" ? "" : "{Urp602019}"))
```

登录按钮的内联脚本：

```js
j_password = hex_md5(hex_md5(pwd), '1.8') + '*' + hex_md5(hex_md5(pwd, '1.8'), '1.8')
```

展开后：

```
左 = MD5( MD5(pwd + "{Urp602019}") )     // 内层加盐，外层不加
右 = MD5( MD5(pwd) )                      // 都不加盐
j_password = 左 + "*" + 右
```

**左右不对称**，这是最容易写错的地方。实现见 `lib/core/urp_crypto.dart`。

测试向量（`pwd = "123456"`）：

```
ca1b3db944006232ca6c5f3e8137c271*14e1b600b1fd579f47433b88e8d85291
```

### 失败签名

```
302 -> /login?errorCode=badCaptcha
```

实测确认（假账号 + 假验证码）。说明字段名与 Cookie 处理全部正确。
已知错误码：`badCaptcha`；`badCredentials` / `invalidSession` / `locked` 为同族系统
常见值，待真实账号校准。

### 学生端 URL 地图（已确认路径有效）

从登录后首页菜单里扒出来的真实入口，全部 302 到 `gotoLogin` 说明路径对、只是没会话：

| 功能 | 路径 |
|---|---|
| 全部及格成绩 | `/student/integratedQuery/scoreQuery/allPassingScores/index` |
| 本学期成绩 | `/student/integratedQuery/scoreQuery/thisTermScores/index` |
| 不及格成绩 | `/student/integratedQuery/scoreQuery/unpassedScores/index` |
| 按方案成绩 | `/student/integratedQuery/scoreQuery/schemeScores/index` |
| 课程属性成绩 | `/student/integratedQuery/scoreQuery/coursePropertyScores/index` |
| 本学期课表 | `/student/courseSelect/thisSemesterCurriculum/index` |
| 校历课表 | `/student/courseSelect/calendarSemesterCurriculum/index` |
| 周课表 | `/student/personalSenate/giveLessonInfo/thisSemesterSchedule/weekLySchedule` |
| 考试安排 | `/student/examinationManagement/examPlan/index` |
| 考试成绩 | `/student/examinationManagement/examGrade/index` |
| 空闲教室 | `/student/teachingResources/freeClassroom/index` |
| 学籍信息 | `/student/rollManagement/rollInfo/index` |
| 学业预警 | `/student/personalManagement/warningInfo/queryWarningInfo` |
| 学生申请 | `/student/application/index` |
| 选课 | `/student/courseSelect/courseSelect/index` |
| 选课结果 | `/student/courseSelect/courseSelectResult/index` |
| 计划完成度 | `/student/integratedQuery/planCompletion/index` |

### 真正的数据接口（关键）

**URP 的成绩页表格是空壳**，页面里用 JS 拼字符串建表，真实数据由一个 AJAX
回调返回 JSON。所以不要解析表格，直接调接口。

路径里带一段**随机字符**（每个页面不同，实测 `8U5kzu4lLM` / `jN408Xn3PK` /
`CUw393pY7N` / `2174F9FA31` / `1kdaM5n42r` / `19432og294`），只能运行时从页面 HTML 里提取：

```js
var url = "/student/integratedQuery/scoreQuery/8U5kzu4lLM/allPassingScores/callback";
$.get(url, function (data) { ... data.lnList ... });
```

| 功能 | 数据接口 |
|---|---|
| 全部及格成绩 | `/student/integratedQuery/scoreQuery/{token}/allPassingScores/callback` |
| 本学期成绩 | `/student/integratedQuery/scoreQuery/{token}/thisTermScores/data` |
| 不及格成绩 | `/student/integratedQuery/scoreQuery/{token}/unpassedScores/callback` |
| 按方案成绩 | `/student/integratedQuery/scoreQuery/{token}/schemeScores/callback` |
| 课程属性成绩 | `/student/integratedQuery/scoreQuery/{token}/coursePropertyScores/callback` |
| 本学期课表 | `/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback`（无 token） |
| 校历课表 | `/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback` |
| 培养方案 | `/student/integratedQuery/instructionPlanQuery/{token}/detail/callback` |
| 学业预警 | `/main/queryWarningDetailedInfo` |
| 学分检查 | `/student/courseSelect/creditCheck/queryAll` |

### 成绩 JSON 结构（从页面 JS 反推）

```json
{"lnList":[{
   "cjbh":"2024-2025秋",   // 学期，用于标签页
   "cjlx":"主修",           // 成绩类型
   "zms":"12",             // 总门数
   "yxxf":"30",            // 已修学分
   "yqxf":"40",            // 要求学分
   "cjList":[{
     "id":{"courseNumber":"MATH1001","coureSequenceNumber":"...",},
     "courseName":"高等数学",
     "courseAttributeName":"必修",
     "credit":"5",
     "courseScore":"92",
     "gradeName":"4.2"
   }]
}]}
```

注意学校代码里把 `courseSequenceNumber` 拼成了 **`coureSequenceNumber`**（少了 s），
照抄别改。

### 课表 JSON 结构（已对照真实响应核实）

`GET /student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback`
（路径里**没有**随机段）。实测顶层键：

| 字段 | 实际类型 | 含义 |
|---|---|---|
| `xkxx` | `[ {课程key: 课程对象} ]` | 数组只含 1 个元素，元素是 `课程号_课序号 → 课程` 的映射 |
| `allUnits` | **数字** | 本学期总学分（实测 26.75），不是数组 |
| `jcsjbs` | 数组 | 节次作息：`{"jc":"1","kssj":"0820","jssj":"0905"}` |
| `csz` | 字符串 | `"1"` 时课表额外显示时间/地点 |
| `dateList` | 数组 | 培养方案信息，含 `selectCourseList` |
| `rwbgLists` | 数组 | 调课/变更，本次为空 |

课程对象实测字段（14 门课）：

| 字段 | 示例 |
|---|---|
| `courseName` | 思想道德与法治 |
| `attendClassTeacher` | `武雅君* `（星号=主讲，末尾有空格） |
| `unit` | 3（学分） |
| `coursePropertiesName` | 必修 |
| `courseCategoryName` | 2公共必修课 |
| `studyModeName` | 正常 |
| `selectCourseStatusName` | 置入 |
| `skzcs` | 4-15周 |
| `id.coureNumber` | 11711113 |
| `id.coureSequenceNumber` | 01 |
| `timeAndPlaceList` | 见下 |

`timeAndPlaceList` 元素（上课时间地点，一门课可多段）：

```json
{"campusName":"东区","teachingBuildingName":"第二公共教学楼","classroomName":"A415",
 "classDay":2,"classSessions":5,"continuingSession":2,
 "classWeek":"000111111111111000000000","weekDescription":"4-15周"}
```

- `classDay`：1=周一
- `classSessions`：起始节次
- `continuingSession`：连堂节数
- `classWeek`：24 位 0/1 串，下标 0 是第 1 周 —— 渲染周课表就靠它

> 又一次踩到学校的拼写：`coureNumber` / `coureSequenceNumber`（少了 s），
> 和成绩接口里的 `coureSequenceNumber` 是同一个毛病。

### 还没解决的

- **成绩全为空**：`allPassingScores` → `{"lnList":[],"state":"0","zxjxjhh":""}`，
  `thisTermScores` → `[{"state":"1","list":[]}]`，`schemeScores` → `{"lnList":[]}`。
  结合本学期课表（思想道德与法治、大学英语一级、高等数学C(理三1)、军事技能）
  判断是**大一第一学期、还没有已结束的课程**，属正常，不是接口错。
  成绩解析器只能用构造数据验证，等期末有成绩后再回归一次。
- **部分接口只吃 POST**：`unpassedScores/callback` 用 GET 返回
  `405 Request method 'GET' not supported`；`instructionPlanQuery` 缺 `fajhh`
  参数返回 400；`creditCheck/queryAll` 返回 `{"status":"203","msg":"null"}`。
  需要按页面的表单参数补 POST。
- **考试安排页当前无数据**：正文是「还没有和你相关的考试信息！」，
  页面本身是服务端渲染（无 AJAX），有考试时表格会直接出现。

### 页面形态（决定解析策略）

从登录后门户页 `01_root.html`（39,759 字节）实测确认：

- **没有 iframe，也没有 `.load()`** —— 菜单是普通 `<a href="/student/...">` 整页跳转，
  数据由服务端直接渲染进 HTML。**所以解析 HTML 表格是对的路子，不存在 JSON 接口。**
- 分页是**前端做的**（`urpjs.js` 里的 `pagination()` / `turntopage()`），
  意味着一次请求就返回全表，抓一页即可，不用翻页。
- AJAX 响应统一带 `status` 字段，`203` 表示业务错误（`urpajax.js` 里全局拦截）。
- 门户页隐藏字段：`xxbm` / `school_id` = `100018`（与登录页 `schoolId` 一致）。

### 踩过的坑

**`/logout` 会把会话登出，爬虫绝不能碰。**
首页有「退出系统」链接，第一版工具把它当普通链接抓了，导致之后所有
`/student/...` 全部 302 到 `gotoLogin`，看起来像"登录失败"，实际是自杀。

`tools/spike.mjs` 里已加 `SKIP_PATTERN = /logout|enterOut|gotoLogin|signout|exit/i`
双重拦截（链接抽取 + 抓取循环）。

### 待补

- 各页面的具体 DOM 结构（需要 `tools/spike.mjs` 的 dump）
- 成绩/课表页是否有学期参数、是否需要 AJAX 二次请求
- 「教务待办」在 URP 里的对应入口（候选：`application`、`warningInfo`）

---

## 2. 学习通（超星）

### 登录链路

| 步骤 | 请求 | 说明 |
|---|---|---|
| 1 | `GET https://passport2.chaoxing.com/login?fid=&refer=` | 页面含 `#fid` `#refer` `#forbidotherlogin` `#t` |
| 2 | `POST https://passport2.chaoxing.com/fanyalogin` | 见下 |

表单字段：

```
fid=-1
uname=<AES(手机号)>
password=<AES(密码)>
refer=<页面 #refer>
t=true
forbidotherlogin=0
validate=
doubleFactorLogin=0
independentId=0
independentNameId=0
```

### 密码加密

`js/fanya/login.js`：

```js
function encryptByAES(message, key) {
  let CBCOptions = { iv: CryptoJS.enc.Utf8.parse(key),
                     mode: CryptoJS.mode.CBC,
                     padding: CryptoJS.pad.Pkcs7 };
  ...
  return CryptoJS.enc.Base64.stringify(encrypted.ciphertext);
}
// transferKey = "u2oh6Vu^HWe4_AES"
```

要点：AES-128-CBC，**key 和 IV 是同一串**（UTF-8 的 16 字节），PKCS7，
输出为 ciphertext 的 Base64（**没有** `Salted__` 前缀）。

是否加密由页面 `#t` 决定，实测为 `"true"`。

实现见 `lib/core/chaoxing_crypto.dart`。

测试向量：

```
AES("13800138000") = yYcVatS+4J+JGnm88UM56A==
AES("Test@1234")   = NDq7emAD7il71U6Ba3I2fA==
AES("2023123456")  = mKYmUkeaF8ngu21LtGHlyw==
AES("a")           = 8nF+VjieNCFu+PDbVN5etg==
```

### 成功 / 失败签名

失败（实测）：

```json
{"msg2":"用户名或密码错误","status":false}
```

成功时 `status: true`，并返回 `url` 供跳转。注意错误信息字段是 **`msg2`**。

### 机构号（fid）

`GET https://passport2.chaoxing.com/org/searchUnis?filter=<名称>&product=44&type=`

天工大相关结果（实测返回）：

| 名称 | schoolid | 备注 |
|---|---|---|
| 天津工业大学 | 33103 | 主校，industry=9 |
| 天津工业大学 | 2276 | industry=5 |
| 天津工业大学 | 177702 | 无 dxfid |
| 天津工业大学图书馆 | 27727 | 图书馆，用于移动图书馆绑定 |

### 作业列表（URL 公式已完全解出）

课程页导航里作业那一项是 `<li dataname="zy" ...><a data-url="https://mooc1.chaoxing.com/mooc2/work/list">`。
参数不是硬编码的，由 `https://mooc2-ans.chaoxing.com/mooc2-ans/js/course-stu.js` 点击时拼出来：

```js
// 点击导航的处理函数（course-stu.js:2158 起）
var url = $(this).find("a").attr("data-url");
if (url.indexOf("?") == -1) url += "?"; else url += "&";

// module == "zy"（作业）
url += "courseId=" + courseid + "&classId=" + clazzid + "&cpi=" + cpi + "&ut=s";
// …（一大串 else if 之后）
if (module == 'zy') { pageHeader = 8; var workEnc = $("#workEnc").val(); url += "&enc=" + workEnc; }

// 通用收尾
if (url.indexOf("?cpi=") == -1 && url.indexOf("&cpi=") == -1) url += "&cpi=" + cpi;
if (url.indexOf("?t=")   == -1 && url.indexOf("&t=")   == -1) url += "&t="   + t;
url += "&stuenc=" + enc;      // enc = $("#enc").val()
```

**关键：两个 enc 不是同一个值。** `enc=` 取 `#workEnc`，`stuenc=` 取 `#enc`。
课程页隐藏域实测值（`.../visit/stucoursemiddle?courseid=267530050&clazzid=155823420`）：

```html
<input type="hidden" id="courseid" value="267530050"/>
<input type="hidden" id="clazzid"  value="155823420"/>
<input type="hidden" id="cpi"      value="562623583"/>
<input type="hidden" id="enc"      value="e28148da5e0bac1a6e7911072b661da0"/>  <!-- → stuenc -->
<input type="hidden" id="oldenc"   value="f82df2ca0f0401f464b1efe159ec27da"/>  <!-- 别的模块用 -->
<input type="hidden" id="workEnc"  value="01c2e021f9926dd62a3cf5f8a544913a"/>  <!-- → enc -->
<input type="hidden" id="examEnc"  value="5621ba50339928afd14813a4bed610c8"/>  <!-- 考试用 -->
<input type="hidden" id="openc"    value="840d4323e2694126b12fc1741340920f"/>
<input type="hidden" id="t"        value="1795599010129"/>
```

所以完整请求是：

```
GET https://mooc1.chaoxing.com/mooc2/work/list
    ?courseId=<courseid>&classId=<clazzid>&cpi=<cpi>&ut=s
    &enc=<workEnc>&t=<t>&stuenc=<enc>
```

**失败签名（逐个试出来的）**：

| 请求形态 | 返回 |
|---|---|
| 只有 `courseId&ut=s` | 1164 字节「无效的用户！」 |
| `courseId&classId&cpi&ut=s&t=&stuenc=<oldenc>` | 1167 字节「无权限的操作！」 |
| 带 `&enc=<workEnc>` + `&t=` + `&stuenc=<enc>` | **✅ 7,421 字节，`<title>作业列表</title>`** |

结论：缺的是 `enc=<workEnc>`——`stuenc` 用的是 `#enc`（不是 `#oldenc`），
`enc` 用 `#workEnc`，两个值不一样。2026-11-25 这一轮实测成功，用的是
`dump-cx/x47` / `x48`（同一门课带/不带 `stuenc` 各一份，两者都 200 且 7,421 字节，
说明服务端对 `stuenc` 不严格）。

### 作业列表页的 DOM 形状（当前是空态）

两门课本轮都是「暂无作业」，所以只能确认真实空态的样子：

```html
<div class="main task-list">
  <div class="top-back"><h2>班级-01</h2></div>
  <input type="hidden" id="courseId" value="267530050" />
  <input type="hidden" id="classId"  value="155823420" />
  <input type="hidden" id="cpi"      value="562623583" />
  <input type="hidden" id="enc"      value="01c2e021f9926dd62a3cf5f8a544913a" />
  <div class="has-content">
    <div class="filter">…筛选 全部 / 已完成 / 未完成，进度 0/0…</div>
    <div class="null-data" style="font-size: 14px;">暂无作业</div>
  </div>
</div>
```

- 有作业时服务端不再渲染 `null-data`，条目挂在 `.task-list` 里（推测是 `li`，
  CSS 里只有 `.task-list`、`.statusbg`、`.courseName`、`.listSubmit` 这几个可用选择器）；
  `parseWorkList` 已按「`.task-list` 范围 → `li` → `tr` → 整块」的顺序退化，
  标题优先取 `overhidden`/`title` 类元素，状态优先取 `.statusbg` 角标。
- **注意**：不能只看 `null-data` 是否存在就判空——模板可能把容器一直留着
  （`display:none`），所以只有它内部文字含「暂无」才算真空。
- 分页是 `#page` + `pageDiv`，前端 `pagination()`；一页给全表的假设在作业这里**不成立**，
  以后要按 `pageSize` 翻页。

### 编码坑（重要，方向差点搞反）

超星的编码声明不可信：正文多数其实是 **UTF-8**（哪怕 `content-type` / `<meta>` 写着 gbk），
少数页面才是真 GBK。**只能嗅探，不能信声明**：

```js
try { return new TextDecoder('utf-8', { fatal: true }).decode(buf); }
catch { /* 不是合法 UTF-8，再按声明 / 默认 gbk 解 */ }
```

- 实测样本 `dump-cx/x53_work_..._courseId_846151_ut_s.html`（1164 字节）：
  按 UTF-8 解得「提示 / 无效的用户！」，按 GBK 解得「鎻愮 / 鏃犳晥鐨勭敤鎴凤紒」——**是 UTF-8**。
- 反之，把真正的 GBK 字节按 UTF-8 解会得到「鏃犳潈闄愮殑鎿嶄綔」这类乱码，
  关键词扫描会整页漏掉，还容易误判成「页面里没有这个入口」。
- `spike-cx.mjs` 的 `decodeBody(buf, contentType)` 已按上面的顺序实现。
- **App 端同样要这样做**：Dart 先 `utf8.decode(bytes, allowMalformed: false)`，
  抛 `FormatException` 再走 GBK 分支（需要 `gbk_codec` 之类的包）。
  学习通的 JSON 接口是 UTF-8，不受影响。

第一轮抓了 45 个页面，**一个 JSON 都没抓到**——学习通的列表不是 XHR，而是页面里直接嵌的
或者 App 原生页面。但从课程页（`/mooc-ans/visit/stucoursemiddle`）的导航里挖到了确定地址：

```html
<li dataname="zy" pageHeader="8" id="nav_8739">
  <a href="javascript:void(0);" title="作业"
     data-url="https://mooc1.chaoxing.com/mooc2/work/list">
```

参数取该页自己的 `courseId` / `clazzId` / `cpi`（实测 `267530050 / 155823420 / 562623583`）
外加 `ut=s`，即：

```
GET https://mooc1.chaoxing.com/mooc2/work/list?courseId=<id>&classId=<classId>&cpi=<cpi>&ut=s
```

`tools/spike-cx.mjs` 第二阶段就是按这个逐门课点名抓的，产物 `x??_work_*.html`。

已知限制：用户的课程页只有 2 门课带 `clazzId`（`有机化学`、`有机化学实验`，且都在「已结束课程」里），
其余 11 个 `courseId` 只出现在知识点链接里、没有 `clazzId`，凑不出作业地址。
所以作业数据的完整度取决于有多少门课有课程主页。

另注：学习通首页 `/` 是 95KB 的 JS 外壳，**链接全是 JS 渲染的**，
用 BFS 抓 `href` 抓不到「我的课程」「应用」这些入口——这是第一轮抓空的根因。

### 待补

- 作业列表页的真实 HTML 结构（下一轮 dump 就有了）
- 座位预约接口（座位图 / 预约 / 退座）——见第 3 节，目前连域名都没有
- 泛雅 Web 端 `jxpt.tiangong.edu.cn` 是否比 App 接口更好抓（两条都试）

---

## 3. 图书馆座位预约（超星体系）

来自图书馆官方《[座位预约系统的使用细则](https://lib.tiangong.edu.cn/2023/0828/c4845a87208/page.htm)》：

- 入口在学习通内，绑定单位「天津工业大学图书馆」（`schoolid=27727`）
- 每日 **22:00** 开放次日预约
- 单次最长 15 小时（07:00–22:00），每天最多取消 3 次
- 签到：扫座位二维码 + GPS 定位，**必须现场**，弹性 20 分钟
- 违约：每周满 3 次停用预约，下周一恢复
- 暂离：20 分钟；用餐时段（11:30–13:00 / 17:30–19:00）60 分钟

**结论：预约/退座可以程序化，签到不行，也不该做。**

### 域名探测（2026-11-25，全部失败）

| 候选 | 结果 |
|---|---|
| `tsgseat.chaoxing.com` | DNS 解析失败 |
| `seat.chaoxing.com` | DNS 解析失败 |
| `libseat.chaoxing.com` | DNS 解析失败 |
| `tsg.chaoxing.com` | DNS 解析失败 |
| `i.chaoxing.com/base?fid=27727` | 302 → `passport2.chaoxing.com/login?fid=12`（fid 被无视，说明不是这个用法） |

图书馆官网只有一句话「点击座位预约」([使用流程](https://lib.tiangong.edu.cn/2023/0828/c4845a87207/page.htm))，
`/4845/list.htm` 也没有任何外链。**座位预约是学习通 App 内的原生/微应用页面，没有公开 URL。**

可行的办法只有一个：在学习通里打开「座位预约」，把地址栏地址抄下来，
用 `spike-cx.mjs` 报告页底部的「再抓一个网址」输入框补抓一次。

---

## 4. 图书馆 OPAC（可选，未做）

- 入口 `https://211.81.31.49:8013/tiangong`
- 账号：学号，初始密码 `Tgu@` + 身份证后六位（**非**学习通账号）
- 用途：借阅查询、到期提醒、续借
