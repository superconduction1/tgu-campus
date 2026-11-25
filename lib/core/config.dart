/// 学校各系统的入口常量。
///
/// 这些值全部来自实际抓取，不是猜的：
/// - 教务登录页 `https://jwxs.tiangong.edu.cn/login`
/// - 表单 action `/j_spring_security_check`（Spring Security）
/// - 验证码 `/img/captcha.jpg`，180x60，4 位字符
/// - 隐藏字段 `tokenValue`（32 位 hex），必须从登录页现取
class UrpConfig {
  UrpConfig._();

  static const String host = 'jwxs.tiangong.edu.cn';
  static const String schoolId = '100018';

  static const String loginPath = '/login';
  static const String captchaPath = '/img/captcha.jpg';
  static const String loginPostPath = '/j_spring_security_check';

  /// 登录成功后可能的落地页，按顺序探测。真实入口待抓包确认。
  static const List<String> landingCandidates = <String>[
    '/',
    '/index.jsp',
    '/frame/default/index.jsp',
    '/frame/index.jsp',
  ];

  static Uri get loginUri => Uri.https(host, loginPath);
  static Uri get captchaUri => Uri.https(host, captchaPath);
  static Uri get loginPostUri => Uri.https(host, loginPostPath);

  static Uri page(String path) => Uri.https(host, path);
}

/// URP 学生端真实路径。
///
/// 全部来自登录后首页菜单的实际链接（2026-11 抓取），不是猜的。
/// 注意：`/logout` 会把会话登出，任何自动爬取都必须排除它。
class UrpPaths {
  UrpPaths._();

  static const String allPassingScores =
      '/student/integratedQuery/scoreQuery/allPassingScores/index';
  static const String thisTermScores =
      '/student/integratedQuery/scoreQuery/thisTermScores/index';
  static const String unpassedScores =
      '/student/integratedQuery/scoreQuery/unpassedScores/index';
  static const String schemeScores =
      '/student/integratedQuery/scoreQuery/schemeScores/index';

  static const String thisSemesterCurriculum =
      '/student/courseSelect/thisSemesterCurriculum/index';
  static const String calendarSemesterCurriculum =
      '/student/courseSelect/calendarSemesterCurriculum/index';
  static const String weeklySchedule =
      '/student/personalSenate/giveLessonInfo/thisSemesterSchedule/weekLySchedule';

  static const String examPlan =
      '/student/examinationManagement/examPlan/index';
  static const String examGrade =
      '/student/examinationManagement/examGrade/index';

  static const String freeClassroom =
      '/student/teachingResources/freeClassroom/index';
  static const String rollInfo =
      '/student/rollManagement/rollInfo/index';
  static const String warningInfo =
      '/student/personalManagement/warningInfo/queryWarningInfo';
  static const String application = '/student/application/index';

  /// 学分（学费）确认。菜单上写着「去确认」，有东西待确认时才会亮。
  static const String creditCheck = '/student/courseSelect/creditCheck/index';
  static const String creditCheckQuery = '/student/courseSelect/creditCheck/queryAll';

  /// 学业预警详情。实测无预警时返回 `{"status":200,"msg":"OK","data":"ok"}`。
  static const String warningDetail = '/main/queryWarningDetailedInfo';

  /// 方案完成情况：培养方案 + 每学期完成度（数据在页面的 zTree 里）。
  static const String planCompletion =
      '/student/integratedQuery/planCompletion/index';

  /// 会把会话登出的路径，抓取逻辑必须跳过。
  static const List<String> sessionKillers = <String>[
    '/logout',
    '/enterOut',
    '/gotoLogin',
  ];
}

/// 超星 / 学习通。作业与图书馆座位预约共用同一登录态。
class ChaoxingConfig {
  ChaoxingConfig._();

  /// 泛雅 Web 端：可能比 App 接口更好抓，Spike 阶段两条都试。
  static const String fanyaHost = 'jxpt.tiangong.edu.cn';
  static const String passportHost = 'passport2.chaoxing.com';

  static Uri get fanyaHome => Uri.https(fanyaHost, '/');
  static Uri get passportLogin => Uri.https(passportHost, '/mlogin');

  /// 「我的课程」列表页。实测 4 个 `stucoursemiddle` 链接从这里出。
  static Uri get courseList =>
      Uri.parse('https://mooc1.chaoxing.com/mooc-ans/visit/stuendcourselist');

  /// 真正在用的课程列表接口（POST 表单，返回卡片 HTML 片段）。
  ///
  /// 来自 `mooc-ans/mooc2/js/course/course.js` 的 `getCourseList()`：
  /// ```
  /// url : _HOST_CP2_ + "/visit/courselistdata", type : "post",
  /// data : { courseType, courseFolderId, baseEducation, superstarClass, courseFolderSize }
  /// ```
  /// `courseType=1` 是「进行中」那个 tab（页面隐藏域写的是 0，但默认选中的 tab 是 1）。
  static Uri get courseListData =>
      Uri.parse('https://mooc1.chaoxing.com/mooc-ans/visit/courselistdata');

  /// 作业列表。必须带 `courseId / classId / cpi / ut=s / t / stuenc`，
  /// 少一个就是「无权限的操作！」提示页。
  static Uri get workList =>
      Uri.parse('https://mooc1.chaoxing.com/mooc2/work/list');
}
