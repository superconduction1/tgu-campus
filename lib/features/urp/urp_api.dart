import 'dart:convert';
import 'dart:typed_data';

import '../../core/config.dart';
import '../../core/http.dart';
import '../../core/urp_crypto.dart';
import 'models.dart';
import 'urp_parser.dart';

/// URP 交互中可以直接展示给用户的错误。
class UrpException implements Exception {
  UrpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次登录握手所需的材料：tokenValue 与一张验证码图。
class LoginTicket {
  const LoginTicket({required this.tokenValue, required this.captchaBytes});

  final String tokenValue;
  final Uint8List captchaBytes;
}

/// 登录结果。
class LoginOutcome {
  const LoginOutcome._({required this.success, this.errorCode, this.message});

  const LoginOutcome.success() : this._(success: true);

  const LoginOutcome.failure(String code, String message)
      : this._(success: false, errorCode: code, message: message);

  final bool success;
  final String? errorCode;
  final String? message;

  /// 把服务端 `errorCode` 翻译成能看懂的话。
  /// 已知值来自实测：`badCaptcha`；其余为同族系统的常见码，待登录后校准。
  static const Map<String, String> errorMessages = <String, String>{
    'badCaptcha': '验证码错误或已过期',
    'badCredentials': '学号或密码错误',
    'invalidSession': '会话已失效，请重新登录',
    'locked': '账号已被锁定，请稍后再试',
    'accountLocked': '账号已被锁定，请稍后再试',
    'userNotExist': '账号不存在',
  };
}

class UrpApi {
  UrpApi(this.client);

  final SchoolHttpClient client;

  /// 抓登录页拿 `tokenValue`，顺手取一张验证码。
  ///
  /// 实测顺序不能反：`/login` 只下发网关 Cookie，
  /// `JSESSIONID` 是在请求验证码那一步才建立的。
  Future<LoginTicket> loadLoginTicket() async {
    final HttpResult page = await client.get(UrpConfig.loginUri);
    if (page.statusCode != 200) {
      throw UrpException('登录页返回 HTTP ${page.statusCode}');
    }

    final RegExpMatch? match =
        RegExp(r'id="tokenValue"[^>]*value="([^"]+)"').firstMatch(page.body);
    if (match == null) {
      throw UrpException('登录页里没找到 tokenValue，页面结构可能已改版');
    }

    final HttpResult captcha = await client.get(UrpConfig.captchaUri);
    if (captcha.statusCode != 200 || captcha.bodyBytes.isEmpty) {
      throw UrpException('验证码下载失败（HTTP ${captcha.statusCode}）');
    }

    return LoginTicket(
      tokenValue: match.group(1)!,
      captchaBytes: captcha.bodyBytes,
    );
  }

  /// 提交登录。
  ///
  /// 服务端失败时是 `302 -> /login?errorCode=xxx`，
  /// 所以这里**必须**禁止自动跟随重定向，否则拿不到错误码。
  Future<LoginOutcome> login({
    required String username,
    required String password,
    required String captcha,
    required String tokenValue,
  }) async {
    final HttpResult result = await client.postForm(
      UrpConfig.loginPostUri,
      <String, String>{
        'lang': 'zh',
        'tokenValue': tokenValue,
        'j_username': username,
        'j_password': UrpCrypto.transformPassword(password),
        'j_captcha': captcha,
      },
    );

    if (result.isRedirect) {
      final String location = result.location ?? '';
      final RegExpMatch? code =
          RegExp(r'errorCode=([A-Za-z0-9_]+)').firstMatch(location);
      if (code == null) return const LoginOutcome.success();
      final String value = code.group(1)!;
      return LoginOutcome.failure(
        value,
        LoginOutcome.errorMessages[value] ?? '登录失败（错误码：$value）',
      );
    }

    if (result.statusCode == 200) {
      final RegExpMatch? code =
          RegExp(r'errorCode=([A-Za-z0-9_]+)').firstMatch(result.body);
      if (code != null) {
        final String value = code.group(1)!;
        return LoginOutcome.failure(
          value,
          LoginOutcome.errorMessages[value] ?? '登录失败（错误码：$value）',
        );
      }
      return const LoginOutcome.success();
    }

    throw UrpException('登录请求返回了意外的 HTTP ${result.statusCode}');
  }

  /// 探测登录后的落地页。返回第一个「不是登录页」的响应。
  ///
  /// 具体入口路径待真实登录后校准，见 [UrpConfig.landingCandidates]。
  Future<HttpResult?> probeLanding() async {
    for (final String path in UrpConfig.landingCandidates) {
      final HttpResult result = await client.get(UrpConfig.page(path));
      if (result.statusCode != 200) continue;
      if (result.body.contains('j_spring_security_check')) continue;
      return result;
    }
    return null;
  }

  /// 会话是否还有效。学生页一旦失效就 302 到 `gotoLogin`。
  Future<bool> isSessionValid() async {
    try {
      final HttpResult result =
          await client.get(UrpConfig.page(UrpPaths.thisTermScores));
      return result.statusCode == 200 && !_looksLikeLogin(result);
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeLogin(HttpResult result) {
    if (result.isRedirect) {
      final String location = result.location ?? '';
      return location.contains('gotoLogin') ||
          location.contains('errorCode=invalidSession') ||
          location.contains('/login');
    }
    return result.body.contains('j_spring_security_check');
  }

  /// 统一的取页方法：会话失效抛 [UrpSessionExpiredException]，
  /// 其余非 200 抛 [UrpException]。
  Future<String> fetchPage(String path) async {
    final HttpResult result = await client.get(UrpConfig.page(path));
    if (_looksLikeLogin(result)) {
      throw UrpSessionExpiredException();
    }
    if (result.statusCode != 200) {
      throw UrpException('$path 返回 HTTP ${result.statusCode}');
    }
    return result.body;
  }

  /// 从页面 HTML 里提取 AJAX 数据接口。
  ///
  /// URP 的接口路径带一段随机字符（实测每页不同），只能运行时从页面上读：
  /// ```js
  /// var url = "/student/integratedQuery/scoreQuery/8U5kzu4lLM/allPassingScores/callback";
  /// $.get(url, function (data) { ... });
  /// ```
  /// 注意 `url = "..."` 这种**不带 var** 的写法也要匹配——课表页就是这种：
  /// `function searchSemester() { url = "/student/.../ajaxStudentSchedule/callback"; $.get(url, ...) }`
  static final RegExp _callbackPattern = RegExp(
    r'''(?:var\s+url\s*=|url\s*=|url\s*:|\$\.get\(\s*)\s*["']([^"']+)["']''',
  );

  static String? extractCallbackUrl(String html) {
    for (final RegExpMatch match in _callbackPattern.allMatches(html)) {
      final String path = match.group(1)!;
      if (!path.startsWith('/')) continue;
      if (path.endsWith('/index')) continue;
      if (path.contains('/callback') ||
          path.endsWith('/data') ||
          path.contains('queryAll')) {
        return path;
      }
    }
    return null;
  }

  /// 取一个 AJAX 接口的 JSON。
  Future<Object?> fetchJson(String path) async {
    final HttpResult result = await client.get(
      UrpConfig.page(path),
      headers: <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': UrpConfig.page(UrpPaths.thisTermScores).toString(),
      },
    );
    if (_looksLikeLogin(result)) throw UrpSessionExpiredException();
    if (result.statusCode != 200) {
      throw UrpException('$path 返回 HTTP ${result.statusCode}');
    }
    return jsonDecode(result.body);
  }

  /// 成绩。默认取「全部及格成绩」，[thisTermOnly] 取本学期。
  ///
  /// 优先走页面里的 JSON 接口；拿不到再退回解析 HTML 表格。
  Future<List<ScoreRecord>> fetchScores({bool thisTermOnly = false}) async {
    final String page = await fetchPage(
      thisTermOnly ? UrpPaths.thisTermScores : UrpPaths.allPassingScores,
    );
    final String? api = extractCallbackUrl(page);
    if (api != null) {
      try {
        final List<ScoreRecord> scores =
            UrpParser.parseScoresJson(await fetchJson(api));
        if (scores.isNotEmpty) return scores;
      } on UrpException {
        rethrow;
      } catch (_) {
        // JSON 走不通就退回表格解析
      }
    }
    return UrpParser.parseScores(page);
  }

  /// 不及格成绩。
  Future<List<ScoreRecord>> fetchUnpassedScores() async {
    final String html = await fetchPage(UrpPaths.unpassedScores);
    return UrpParser.parseScores(html);
  }

  /// 考试安排。
  Future<List<ExamRecord>> fetchExams() async {
    final String html = await fetchPage(UrpPaths.examPlan);
    return UrpParser.parseExams(html);
  }

  /// 本学期课表原始 HTML。课表结构复杂，先留原始页面，
  /// 解析器等 dump 确认结构后再写。
  Future<String> fetchTimetableHtml() =>
      fetchPage(UrpPaths.thisSemesterCurriculum);

  /// 本学期课表（走固定的 JSON 接口，路径里没有随机段）。
  Future<Timetable> fetchTimetable() async {
    final Object? json = await fetchJson(
      '/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback',
    );
    return UrpParser.parseTimetableJson(json);
  }

  /// 当前学年 / 学期 / 教学周。
  ///
  /// 教务每个页面的顶部都有这条信息，取首页就够了，
  /// 不需要为了算周次再去抓校历页。
  Future<TermInfo> fetchTermInfo() async {
    final TermInfo? info = UrpParser.parseTermInfo(await fetchPage('/'));
    if (info == null) {
      throw UrpException('页面里没找到学期条，可能改版了');
    }
    return info;
  }

  /// 学业预警 / 待办候选。
  Future<String> fetchWarningHtml() => fetchPage(UrpPaths.warningInfo);

  /// 待办：把教务里几处「可能要你动手」的地方聚合成一张列表。
  ///
  /// 现在能问的三处（实测 2026-11 对大一第一学期全部为空）：
  ///  - 学分确认 `creditCheck/queryAll` → `status 203`，即没有待确认项；
  ///  - 学业预警 `/main/queryWarningDetailedInfo` → `data "ok"`，即没有预警；
  ///  - 学习通作业还没接进来，接进来后也塞这个列表。
  ///
  /// 单个接口失败不该让整页白屏，所以各自吞异常；
  /// 但会话过期要往外抛，让 UI 去重新登录。
  Future<List<TodoItem>> fetchTodos() async {
    final List<TodoItem> todos = <TodoItem>[];

    try {
      final Object? credit = await fetchJson(UrpPaths.creditCheckQuery);
      if (UrpParser.hasCreditConfirmPending(credit)) {
        todos.add(const TodoItem(
          title: '学分确认还没做',
          detail: '教务菜单上写着「去确认」，进去核对后提交',
          kind: TodoKind.creditConfirm,
          path: UrpPaths.creditCheck,
        ));
      }
    } on UrpSessionExpiredException {
      rethrow;
    } catch (_) {
      // 接口临时不通就不显示这一项，不打断整个待办页。
    }

    try {
      final Object? warn = await fetchJson(UrpPaths.warningDetail);
      for (final String text in UrpParser.parseWarnings(warn)) {
        todos.add(TodoItem(
          title: text,
          detail: '学业预警',
          kind: TodoKind.warning,
          path: UrpPaths.warningInfo,
        ));
      }
    } on UrpSessionExpiredException {
      rethrow;
    } catch (_) {
      // 同上。
    }

    return todos;
  }
}

/// 会话过期。UI 上要能区分「网络坏了」和「要重新登录」。
class UrpSessionExpiredException extends UrpException {
  UrpSessionExpiredException() : super('登录已过期，请重新登录');
}
