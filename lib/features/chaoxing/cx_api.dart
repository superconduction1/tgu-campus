import 'dart:async';
import 'dart:convert';

import '../../core/chaoxing_crypto.dart';
import '../../core/config.dart';
import '../../core/http.dart';
import 'cx_parser.dart';
import 'models.dart';

/// 手动跟过 3xx 之后的结果：最终地址 + 最终响应。
class _Fetched {
  const _Fetched({required this.uri, required this.result});

  final Uri uri;
  final HttpResult result;
}

/// 学习通登录结果。
class CxLoginOutcome {
  const CxLoginOutcome._({
    required this.success,
    this.message,
    this.redirect,
  });

  const CxLoginOutcome.success({String? redirect})
      : this._(success: true, redirect: redirect);

  const CxLoginOutcome.failure(String message)
      : this._(success: false, message: message);

  final bool success;
  final String? message;
  final String? redirect;
}

/// 学习通（超星）客户端。
///
/// 只覆盖这个项目要用的部分：登录、作业列表、座位预约。
/// 作业和座位的数据接口需要真实账号抓包后补齐，登录链路已经按
/// `login.js` 原样实现。
class ChaoxingApi {
  ChaoxingApi(this.client);

  final SchoolHttpClient client;

  /// 页面上的隐藏字段，决定这次登录要不要加密、用哪个机构号。
  ({String fid, String refer, String forbidOtherLogin, bool encrypt})
      _loginFormFields(String html) {
    String pick(String id) {
      final RegExpMatch? m = RegExp(
        'id="$id"[^>]*value="([^"]*)"',
      ).firstMatch(html);
      return m?.group(1) ?? '';
    }

    return (
      fid: pick('fid').isEmpty ? '-1' : pick('fid'),
      refer: pick('refer'),
      forbidOtherLogin: pick('forbidotherlogin').isEmpty
          ? '0'
          : pick('forbidotherlogin'),
      encrypt: pick('t') == 'true',
    );
  }

  /// 手机号 + 密码登录。
  ///
  /// `fid` 留空时走学习通公共账号（`-1`）；要进学校专属空间再单独绑单位。
  Future<CxLoginOutcome> login({
    required String phone,
    required String password,
    String? fid,
  }) async {
    final HttpResult page = await client.get(ChaoxingConfig.passportLogin);
    if (page.statusCode != 200) {
      return CxLoginOutcome.failure('登录页返回 HTTP ${page.statusCode}');
    }
    final ({String fid, String refer, String forbidOtherLogin, bool encrypt})
        fields = _loginFormFields(page.body);

    final String uname =
        fields.encrypt ? ChaoxingCrypto.encrypt(phone) : phone;
    final String pwd =
        fields.encrypt ? ChaoxingCrypto.encrypt(password) : password;

    final HttpResult result = await client.postForm(
      Uri.https(ChaoxingConfig.passportHost, '/fanyalogin'),
      <String, String>{
        'fid': fid ?? fields.fid,
        'uname': uname,
        'password': pwd,
        'refer': fields.refer,
        't': fields.encrypt.toString(),
        'forbidotherlogin': fields.forbidOtherLogin,
        'validate': '',
        'doubleFactorLogin': '0',
        'independentId': '0',
        'independentNameId': '0',
      },
    );

    if (result.statusCode != 200) {
      return CxLoginOutcome.failure('登录请求返回 HTTP ${result.statusCode}');
    }

    Map<String, dynamic>? json;
    try {
      final Object? decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }
    if (json == null) {
      return const CxLoginOutcome.failure('登录接口返回的不是 JSON，可能触发了风控');
    }

    final bool ok = json['status'] == true || json['status'] == 1;
    if (!ok) {
      // 实测失败响应长这样：{"msg2":"用户名或密码错误","status":false}
      // 注意是 msg2，不是 msg。
      final String msg =
          (json['msg2'] ?? json['msg'] ?? json['message'] ?? '登录失败')
              .toString();
      return CxLoginOutcome.failure(msg);
    }

    final Object? url = json['url'];
    return CxLoginOutcome.success(redirect: url?.toString());
  }

  // --- 作业 ---

  /// 「我的课程」列表。
  ///
  /// 页面 `visit/interaction` 本身是空壳，卡片由 `course.js` 的
  /// `getCourseList()` POST `visit/courselistdata` 拿回来再塞进 `#courselistArea`。
  /// 所以这里直接打那个接口——不然只能拿到「已结束课程」那两门。
  Future<List<CxCourse>> fetchCourses() async {
    final HttpResult r = await client.postForm(
      ChaoxingConfig.courseListData,
      <String, String>{
        'courseType': '1', // 进行中
        'courseFolderId': '0',
        'baseEducation': '0',
        'superstarClass': '',
        'courseFolderSize': '0',
      },
    );
    if (r.statusCode != 200) {
      throw CxDeniedException('课程列表返回 ${r.statusCode}');
    }
    final List<CxCourse> courses = parseCourseList(r.html);
    if (courses.isNotEmpty) return courses;

    // 兜底：老接口（只有已结束课程时才有内容）
    final HttpResult fallback = await client.get(ChaoxingConfig.courseList);
    if (fallback.statusCode != 200) {
      throw CxDeniedException('课程列表返回 ${fallback.statusCode}');
    }
    return parseCourseList(fallback.html);
  }

  /// 单门课的作业：课程页取隐藏域 → 拼作业 URL → 解析。
  ///
  /// 隐藏域是必须的：少了 `t` 和 `stuenc`，服务端直接回「无权限的操作！」。
  Future<HomeworkList> fetchCourseHomework(CxCourse course) async {
    final Uri pageUri = course.pageUrl.isNotEmpty
        ? Uri.parse(course.pageUrl)
        : _canonicalCourseUri(course);

    // 课程列表给的是「新版界面」链接（带 ismooc2=1），那页没有隐藏域。
    CourseContext? ctx;
    String lastFingerprint = '一个页面都没取到';
    Uri lastUri = pageUri;
    for (final Uri candidate in <Uri>[
      normalizeCoursePageUri(pageUri),
      _canonicalCourseUri(course),
    ]) {
      final _Fetched page = await _getFollowing(candidate);
      lastFingerprint = pageFingerprint(page.result.html,
              statusCode: page.result.statusCode) +
          '，最终地址 ${page.uri.path}';
      lastUri = page.uri;
      ctx = parseCourseContext(page.result.html);
      if (ctx != null) break;
    }
    if (ctx == null) {
      // 把最后那页长什么样写进错误里，用户复制自检报告就能直接定位。
      final bool toLogin =
          lastUri.host.contains('passport2') || lastUri.host.contains('login');
      throw CxDeniedException(
        toLogin
            ? '${course.name}：跳到了登录页，学习通登录态过期了，去「设置 → 学习通」重新登录'
            : '${course.name}：课程页里没有 courseid/clazzid；'
                '最后取的页面是 $lastFingerprint',
      );
    }
    final HttpResult list =
        await client.get(buildWorkListUrl(ctx, ChaoxingConfig.workList));
    return parseWorkList(list.html, courseName: course.name);
  }

  Uri _canonicalCourseUri(CxCourse course) =>
      Uri.https('mooc1.chaoxing.com', '/mooc-ans/visit/stucoursemiddle', <String, String>{
        'courseid': course.courseId,
        'clazzid': course.clazzId,
        'cpi': course.cpi,
        'vc': '1',
      });

  /// 手动跟 3xx。
  ///
  /// `SchoolHttpClient` 是 `followRedirects = false` 的（登录要靠 302 的
  /// Location 判错），所以课程页遇到 302 时必须自己跟一遍——实测
  /// 「26军事理论」的课程页就是 302 + 0 字节，不跟就拿不到隐藏域。
  Future<_Fetched> _getFollowing(Uri uri, {int maxHops = 3}) async {
    Uri current = uri;
    HttpResult result = await client.get(current);
    int hops = 0;
    while (hops < maxHops && _isRedirect(result.statusCode)) {
      final String? location = result.location;
      if (location == null || location.isEmpty) break;
      current = current.resolve(location);
      result = await client.get(current);
      hops++;
    }
    return _Fetched(uri: current, result: result);
  }

  static bool _isRedirect(int code) =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  /// 全部课程的作业。
  ///
  /// 单门课失败不拖垮整页：失败的记进 `failures`；
  /// 但如果**一门都没成功**，说明是会话或网络问题，直接把第一个异常抛出去。
  ///
  /// 11 门课串行要十来秒，所以这里按 [concurrency] 并发，并且每门课单独限时
  /// （[perCourseTimeout]）——某门课卡住只算它失败，不会把整页拖死。
  Future<HomeworkList> fetchHomework({
    int concurrency = 3,
    Duration perCourseTimeout = const Duration(seconds: 12),
  }) async {
    final List<CxCourse> courses = await fetchCourses();
    if (courses.isEmpty) {
      return const HomeworkList();
    }

    final List<CxCourse> usable = courses
        .where((CxCourse c) => c.isUsable)
        .toList(growable: false);
    final List<HomeworkList> ok = <HomeworkList>[];
    final List<String> failures = <String>[];
    Object? firstError;
    int next = 0;

    Future<void> worker() async {
      while (next < usable.length) {
        final CxCourse c = usable[next++];
        try {
          ok.add(await fetchCourseHomework(c).timeout(perCourseTimeout));
        } on CxDeniedException catch (e) {
          firstError ??= e;
          failures.add('${c.name}：${e.message}');
        } on TimeoutException catch (e) {
          firstError ??= e;
          failures.add('${c.name}：超过 ${perCourseTimeout.inSeconds} 秒没响应');
        } catch (e) {
          firstError ??= e;
          failures.add('${c.name}：$e');
        }
      }
    }

    final int lanes = concurrency < 1
        ? 1
        : (concurrency > 5 ? 5 : concurrency);
    await Future.wait(<Future<void>>[
      for (int i = 0; i < lanes; i++) worker(),
    ]);

    // firstError 在闭包里被赋值，没法直接判空后 throw（提不上类型），先落到局部变量。
    final Object? first = firstError;
    if (ok.isEmpty && first != null) {
      throw first;
    }
    final HomeworkList merged = HomeworkList.merge(ok);
    return HomeworkList(
      items: merged.items,
      failures: <String>[...failures, ...merged.failures],
    );
  }

  /// 座位预约：座位图 / 预约 / 退座。等拿到学习通内「座位预约」的入口地址再实现。
  Future<void> fetchSeats() async {
    throw UnimplementedError('学习通座位预约地址未知，等用户提供入口');
  }
}
