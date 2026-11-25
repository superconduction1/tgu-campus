import 'dart:convert';

import '../../core/chaoxing_crypto.dart';
import '../../core/config.dart';
import '../../core/http.dart';
import 'cx_parser.dart';
import 'models.dart';

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

  /// 「我的课程」列表。会话掉了会跳到登录页，这里当失败处理。
  Future<List<CxCourse>> fetchCourses() async {
    final HttpResult r = await client.get(ChaoxingConfig.courseList);
    if (r.statusCode != 200) {
      throw CxDeniedException('课程列表返回 ${r.statusCode}');
    }
    return parseCourseList(r.html);
  }

  /// 单门课的作业：课程页取隐藏域 → 拼作业 URL → 解析。
  ///
  /// 隐藏域是必须的：少了 `t` 和 `stuenc`，服务端直接回「无权限的操作！」。
  Future<HomeworkList> fetchCourseHomework(CxCourse course) async {
    final Uri pageUri = course.pageUrl.isNotEmpty
        ? Uri.parse(course.pageUrl)
        : Uri.parse('https://mooc1.chaoxing.com/mooc-ans/visit/stucoursemiddle'
            '?courseid=${course.courseId}&clazzid=${course.clazzId}'
            '&cpi=${course.cpi}');
    final HttpResult page = await client.get(pageUri);
    final CourseContext? ctx = parseCourseContext(page.html);
    if (ctx == null) {
      throw CxDeniedException('${course.name}：课程页里没有隐藏域，会话可能已失效');
    }
    final HttpResult list =
        await client.get(buildWorkListUrl(ctx, ChaoxingConfig.workList));
    return parseWorkList(list.html, courseName: course.name);
  }

  /// 全部课程的作业。
  ///
  /// 单门课失败不拖垮整页：失败的记进 `failures`；
  /// 但如果**一门都没成功**，说明是会话或网络问题，直接把第一个异常抛出去。
  Future<HomeworkList> fetchHomework() async {
    final List<CxCourse> courses = await fetchCourses();
    if (courses.isEmpty) {
      return const HomeworkList();
    }

    final List<HomeworkList> ok = <HomeworkList>[];
    final List<String> failures = <String>[];
    Object? firstError;

    for (final CxCourse c in courses) {
      if (!c.isUsable) continue;
      try {
        ok.add(await fetchCourseHomework(c));
      } on CxDeniedException catch (e) {
        firstError ??= e;
        failures.add('${c.name}：${e.message}');
      } catch (e) {
        firstError ??= e;
        failures.add('${c.name}：$e');
      }
    }

    if (ok.isEmpty && firstError != null) {
      throw firstError;
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
