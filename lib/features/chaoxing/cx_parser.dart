/// 学习通页面的解析。
///
/// 两个原则：
/// 1. **按结构特征找，不按 DOM 路径找**——超星的页面改版很勤，
///    但只要「课程名在 `course-name` 的 title 里」「作业状态是那几组汉字」
///    这些约定还在，解析就不会整页崩。
/// 2. **失败要能说清楚**——缺参数时服务端回的是 1164 字节的提示页
///    （「无权限的操作！」/「无效的用户！」），必须显式抛异常，
///    而不是当成「这门课没有作业」静默返回空。
library;

import 'models.dart';

/// 服务端因为参数/会话不对，直接回了提示页。
class CxDeniedException implements Exception {
  const CxDeniedException(this.message);

  final String message;

  @override
  String toString() => '学习通拒绝访问：$message';
}

/// 提示页的特征文案。实测两种：
/// - 带 `courseId+classId+cpi+ut=s` 但缺 `t/stuenc` → 「无权限的操作！」
/// - 只带 `courseId` → 「无效的用户！」
const List<String> _denialMarkers = <String>[
  '无权限的操作',
  '无效的用户',
];

String _stripTags(String html) => html
    .replaceAll(RegExp('<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 解析「我的课程」页，拿到每门课的 `courseId / clazzId / cpi / 名称`。
///
/// 实测 HTML（`mooc-ans/visit/stuendcourselist`）：
/// ```html
/// <a class="color1" href='https://mooc1.chaoxing.com/mooc-ans/visit/stucoursemiddle
///    ?courseid=267530050&clazzid=155823420&vc=1&cpi=562623583&ismooc2=1' target="_blank">
///   <span class="course-name overHidden2" title="有机化学实验">有机化学实验</span>
/// </a>
/// ```
List<CxCourse> parseCourseList(String html) {
  // 同一门课在页面上有两个锚点：一个包封面图（没有名字），一个包课程名。
  // 所以先按 courseId/clazzId 归并，再让有名字的那个覆盖掉空的。
  final Map<String, CxCourse> byKey = <String, CxCourse>{};

  for (final RegExpMatch m
      in RegExp(r'<a\b[^>]*stucoursemiddle[^>]*>[\s\S]{0,400}?</a>',
              caseSensitive: false)
          .allMatches(html)) {
    final String block = m.group(0)!;
    final RegExpMatch? href =
        RegExp(r'''href=['"]([^'"]+)['"]''').firstMatch(block);
    if (href == null) continue;

    final Uri? uri = Uri.tryParse(href.group(1)!);
    if (uri == null) continue;

    final String courseId = uri.queryParameters['courseid'] ??
        uri.queryParameters['courseId'] ??
        '';
    final String clazzId =
        uri.queryParameters['clazzid'] ?? uri.queryParameters['clazzId'] ?? '';
    final String cpi = uri.queryParameters['cpi'] ?? '';
    if (courseId.isEmpty) continue;

    // 名称优先取 title 属性（不带「更多」之类的装饰），退回可见文字。
    String name = '';
    final RegExpMatch? title =
        RegExp(r'''title=["']([^"']+)["']''').firstMatch(block);
    if (title != null) name = title.group(1)!.trim();
    if (name.isEmpty) name = _stripTags(block);

    final String key = '$courseId/$clazzId';
    final CxCourse? existing = byKey[key];
    if (existing != null && existing.name.isNotEmpty) continue;
    byKey[key] = CxCourse(
      courseId: courseId,
      clazzId: clazzId,
      cpi: cpi,
      name: name,
      pageUrl: href.group(1)!,
    );
  }
  return byKey.values.toList(growable: false);
}

/// 从课程页的隐藏域里取拼作业 URL 的参数。
///
/// 实测：`courseid=267530050`、`clazzid=155823420`、`cpi=562623583`、
/// `oldenc=f82df2ca...`、`t=1795598066314`。
CourseContext? parseCourseContext(String html) {
  String pick(String id) {
    final RegExp a = RegExp(
      '<input[^>]*id=["\']$id["\'][^>]*value=["\']([^"\']*)["\']',
      caseSensitive: false,
    );
    final RegExp b = RegExp(
      '<input[^>]*value=["\']([^"\']*)["\'][^>]*id=["\']$id["\']',
      caseSensitive: false,
    );
    final RegExpMatch? m = a.firstMatch(html) ?? b.firstMatch(html);
    return m?.group(1) ?? '';
  }

  final CourseContext ctx = CourseContext(
    courseId: pick('courseid'),
    clazzId: pick('clazzid'),
    cpi: pick('cpi'),
    t: pick('t'),
    enc: pick('enc'),
    workEnc: pick('workEnc'),
    openc: pick('openc'),
  );
  return ctx.isUsable ? ctx : null;
}

/// 课程列表里的链接带 `ismooc2=1`，进去是「新版课程界面」，
/// 那个页面没有 `courseid/clazzid/enc` 这些隐藏域；去掉它才是老界面。
///
/// 实测：带 `ismooc2=1` 的页面解析不出隐藏域，去掉后立刻能拿到。
Uri normalizeCoursePageUri(Uri page) {
  if (!page.queryParameters.containsKey('ismooc2')) {
    return page;
  }
  final Map<String, String> q = <String, String>{
    ...page.queryParameters,
  }..remove('ismooc2');
  return page.replace(queryParameters: q);
}

/// 拼作业列表 URL。
///
/// 逐字对照 `course-stu.js` 的 `module == 'zy'` 分支：
/// ```
/// url += "courseId=" + courseid + "&classId=" + clazzid + "&cpi=" + cpi + "&ut=s";
/// // ... module == 'zy'
/// url += "&enc=" + $("#workEnc").val();
/// if (url.indexOf("&t=") == -1) url += "&t=" + $("#t").val();
/// url += "&stuenc=" + $("#enc").val();
/// ```
/// 注意两个 enc 不是同一个值：`enc` 取 `#workEnc`，`stuenc` 取 `#enc`。
Uri buildWorkListUrl(
  CourseContext ctx,
  Uri base, {
  bool useStuenc = true,
}) {
  final Map<String, String> query = <String, String>{
    'courseId': ctx.courseId,
    'classId': ctx.clazzId,
    'cpi': ctx.cpi,
    'ut': 's',
  };
  if (ctx.workEnc.isNotEmpty) query['enc'] = ctx.workEnc;
  if (ctx.t.isNotEmpty) query['t'] = ctx.t;
  if (useStuenc && ctx.enc.isNotEmpty) query['stuenc'] = ctx.enc;
  return base.replace(queryParameters: query);
}

/// 解析作业列表。
///
/// 结构容错：先按 `<li>` 分块；分不出来再按 `<tr>`；再不行就整页找带
/// `work` 的链接。每条作业至少要有一个非空标题才算数。
HomeworkList parseWorkList(String html, {String courseName = ''}) {
  for (final String marker in _denialMarkers) {
    if (html.contains(marker)) {
      throw CxDeniedException(marker);
    }
  }
  if (html.trim().isEmpty) return HomeworkList(courseName: courseName);

  // 空态快路径。学习通没有作业时服务端直接渲染
  // `<div class="null-data" style="...">暂无作业</div>`，整页连一个 <li> 都没有，
  // 不分块的话会把导航栏的链接当成作业条目。
  if (_isNullDataPage(html)) return HomeworkList(courseName: courseName);

  final List<String> blocks = _splitBlocks(html);
  final List<HomeworkItem> items = <HomeworkItem>[];
  final Set<String> seen = <String>{};

  for (final String block in blocks) {
    final String url = _pickWorkUrl(block);
    if (url.isEmpty) continue;

    final String title = _pickWorkTitle(block);
    if (title.isEmpty || title.length > 200) continue;
    if (!seen.add('$title|$url')) continue;

    final String text = _stripTags(block);
    final String statusText = _pickStatusText(_pickStatusBadge(block), text);
    final HomeworkItem item = HomeworkItem(
      title: title,
      courseName: courseName,
      status: parseHomeworkStatus(statusText),
      statusText: statusText,
      url: url,
      deadline: _pickDeadline(text),
    );
    items.add(item);
  }

  return HomeworkList(items: items, courseName: courseName);
}

/// 真正的「暂无作业」空态：`null-data` 容器里带着「暂无」字样。
///
/// 只看到 `null-data` 不算数——页面模板可能把这个容器一直留在 DOM 里
/// （有作业时用 `display:none` 藏起来），那样会误判成没有作业。
bool _isNullDataPage(String html) {
  final RegExp re = RegExp(
    r'''class=["'][^"']*null-data[^"']*["'][^>]*>([\s\S]{0,200}?)</div>''',
    caseSensitive: false,
  );
  final RegExpMatch? m = re.firstMatch(html);
  if (m == null) return false;
  final String text = _stripTags(m.group(1)!).trim();
  return text.contains('暂无') || text.isEmpty;
}

List<String> _splitBlocks(String html) {
  // 学习通的作业条目都挂在 `.task-list` 里，先缩到这个范围，
  // 免得把顶部导航、筛选栏的 <li> 也算进来（筛选栏确实是一串 <li>）。
  final String scope = _taskListScope(html);

  final List<String> byLi = <String>[
    for (final RegExpMatch m
        in RegExp(r'<li\b[\s\S]*?(?=<li\b|</ul>)', caseSensitive: false)
            .allMatches(scope))
      m.group(0)!,
  ];
  if (byLi.any(_hasWorkLink)) return byLi;

  final List<String> byTr = <String>[
    for (final RegExpMatch m
        in RegExp(r'<tr\b[\s\S]*?</tr>', caseSensitive: false)
            .allMatches(scope))
      m.group(0)!,
  ];
  if (byTr.any(_hasWorkLink)) return byTr;

  return <String>[scope];
}

/// 截取 `.task-list` 之后的部分；找不到就整页。
String _taskListScope(String html) {
  final int at = html.indexOf('task-list');
  return at < 0 ? html : html.substring(at);
}

bool _hasWorkLink(String block) => _pickWorkUrl(block).isNotEmpty;

/// 取条目链接：优先带 `work`/`homework` 的锚点，其次块内第一个锚点。
String _pickWorkUrl(String block) {
  final Iterable<RegExpMatch> anchors = RegExp(
    r'''<a\b[^>]*href=["']([^"']+)["']''',
    caseSensitive: false,
  ).allMatches(block);
  String first = '';
  for (final RegExpMatch m in anchors) {
    final String href = m.group(1)!;
    if (href.isEmpty || href.startsWith('javascript') || href.startsWith('#')) {
      continue;
    }
    final String lower = href.toLowerCase();
    if (lower.contains('work') || lower.contains('homework')) return href;
    if (first.isEmpty) first = href;
  }
  return first;
}

/// 取条目标题：`overhidden`/`title` 类元素优先，其次锚点文字。
String _pickWorkTitle(String block) {
  final RegExpMatch? titled = RegExp(
    r'''<[a-z0-9]+\b[^>]*class=["'][^"']*(?:overhidden|overHidden|title)[^"']*["'][^>]*>([\s\S]*?)</''',
    caseSensitive: false,
  ).firstMatch(block);
  if (titled != null) {
    final String text = _stripTags(titled.group(1)!);
    if (text.isNotEmpty && text.length <= 200) return text;
  }

  final RegExpMatch? anchor = RegExp(
    r'''<a\b[^>]*>([\s\S]*?)</a>''',
    caseSensitive: false,
  ).firstMatch(block);
  if (anchor != null) {
    final String text = _stripTags(anchor.group(1)!);
    if (text.isNotEmpty && text.length <= 200) return text;
  }
  return '';
}

/// 状态角标 `.statusbg` 的文字（学习通把「未提交/已提交」放这里）。
String _pickStatusBadge(String block) {
  final RegExpMatch? badge = RegExp(
    r'''class=["'][^"']*statusbg[^"']*["'][^>]*>([\s\S]{0,40}?)</''',
    caseSensitive: false,
  ).firstMatch(block);
  return badge == null ? '' : _stripTags(badge.group(1)!).trim();
}

/// 在一段文字里找出状态词。按「越具体越靠前」的顺序试，
/// 命中就返回命中的那个词本身（界面要显示原文）。
///
/// [badge] 是 `.statusbg` 角标里的原文；角标命中就用角标，
/// 否则退回整块文字——整块里可能先出现「未提交」这类说明性文字。
String _pickStatusText(String badge, String text) {
  const List<String> words = <String>[
    '未提交',
    '待提交',
    '未交',
    '待批阅',
    '批阅中',
    '已提交',
    '已交',
    '已批阅',
    '已评分',
    '已过期',
  ];
  for (final String w in words) {
    if (badge.contains(w)) return w;
  }
  for (final String w in words) {
    if (text.contains(w)) return w;
  }
  return '';
}

/// 找截止时间。实测页面多是 `2026-11-30 23:59` 这种格式。
String _pickDeadline(String text) {
  final RegExpMatch? m =
      RegExp(r'\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{1,2})?').firstMatch(text);
  return m?.group(0) ?? '';
}
