/// 学习通（超星）侧的数据模型。
///
/// 只放这一项目前真的用得到的东西：课程身份、作业条目。
/// 座位预约要等拿到入口地址再补。
library;

/// 一门课在「我的课程」里的身份。
///
/// 学习通的所有 mooc 接口都靠这三个 id 定位：
/// `courseId`（课程）、`classId`（教学班）、`cpi`（内容包实例）。
class CxCourse {
  const CxCourse({
    required this.courseId,
    required this.clazzId,
    required this.cpi,
    required this.name,
    this.pageUrl = '',
  });

  final String courseId;
  final String clazzId;
  final String cpi;
  final String name;
  final String pageUrl;

  bool get isUsable => courseId.isNotEmpty && clazzId.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is CxCourse &&
      other.courseId == courseId &&
      other.clazzId == clazzId;

  @override
  int get hashCode => Object.hash(courseId, clazzId);

  @override
  String toString() => '$name($courseId/$clazzId)';
}

/// 课程页里那几个隐藏域，作业 URL 就是拿它们拼出来的。
///
/// 公式（逐字来自 `course-stu.js`）：
/// `courseId=..&classId=..&cpi=..&ut=s&t=<t>&stuenc=<oldenc>`
class CourseContext {
  const CourseContext({
    required this.courseId,
    required this.clazzId,
    required this.cpi,
    required this.t,
    required this.enc,
    this.workEnc = '',
    this.openc = '',
  });

  final String courseId;
  final String clazzId;
  final String cpi;
  final String t;

  /// 课程页 `#enc`，拼成 `&stuenc=`。**不是** `#oldenc`。
  final String enc;

  /// 课程页 `#workEnc`，拼成作业列表的 `&enc=`。
  final String workEnc;

  /// 课程页 `#openc`，考试/TODO 那条链路要用。
  final String openc;

  bool get isUsable => courseId.isNotEmpty && clazzId.isNotEmpty;
}

/// 作业状态。文字是服务端直接给的，这里做归一。
enum HomeworkStatus {
  /// 未交 / 待提交
  notSubmitted,

  /// 已交 / 已提交
  submitted,

  /// 待批阅
  grading,

  /// 已批阅 / 已通过
  graded,

  /// 已过期 / 已截止
  expired,

  /// 认不出来就放这里，界面上原样显示原文
  unknown,
}

extension HomeworkStatusLabel on HomeworkStatus {
  String get label => switch (this) {
        HomeworkStatus.notSubmitted => '未交',
        HomeworkStatus.submitted => '已交',
        HomeworkStatus.grading => '待批阅',
        HomeworkStatus.graded => '已批阅',
        HomeworkStatus.expired => '已过期',
        HomeworkStatus.unknown => '未知',
      };

  /// 只有「未交」算待办——首页和待办页要用这个判断。
  bool get isPending => this == HomeworkStatus.notSubmitted;
}

/// 把页面上的中文状态归一成枚举。
///
/// 注意顺序：先判「未交」再判「已交」，否则「未交作业」这种文案会被
/// 误判成「已交」。
HomeworkStatus parseHomeworkStatus(String text) {
  final String t = text.trim();
  if (t.isEmpty) return HomeworkStatus.unknown;
  if (t.contains('未交') || t.contains('待提交') || t.contains('未提交')) {
    return HomeworkStatus.notSubmitted;
  }
  if (t.contains('待批阅') || t.contains('待评分') || t.contains('批阅中')) {
    return HomeworkStatus.grading;
  }
  if (t.contains('已交') || t.contains('已提交')) {
    return HomeworkStatus.submitted;
  }
  if (t.contains('已批阅') || t.contains('已评分') || t.contains('已通过')) {
    return HomeworkStatus.graded;
  }
  if (t.contains('过期') || t.contains('截止') || t.contains('已结束')) {
    return HomeworkStatus.expired;
  }
  return HomeworkStatus.unknown;
}

/// 一条作业。
class HomeworkItem {
  const HomeworkItem({
    required this.title,
    required this.courseName,
    required this.status,
    this.url = '',
    this.deadline = '',
    this.statusText = '',
  });

  final String title;
  final String courseName;
  final HomeworkStatus status;
  final String url;

  /// 截止时间，能解析出来就是 `2026-11-30 23:59` 这种，解析不出来留空。
  final String deadline;

  /// 服务端原文状态，认不出来时直接显示它，别丢信息。
  final String statusText;

  bool get isPending => status.isPending;

  @override
  String toString() => '$courseName · $title · ${status.label}';
}

/// 一门课（或全部课）的作业集合。
class HomeworkList {
  const HomeworkList({
    this.items = const <HomeworkItem>[],
    this.courseName = '',
    this.failures = const <String>[],
  });

  final List<HomeworkItem> items;
  final String courseName;

  /// 拉取失败、但这门课坏了不该拖垮整页时记在这（「有机化学：无权限的操作！」）。
  final List<String> failures;

  int get failedCount => failures.length;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  /// 还没交的条数——首页拿它显示红点。
  int get pendingCount => items.where((HomeworkItem e) => e.isPending).length;

  List<HomeworkItem> get pending =>
      items.where((HomeworkItem e) => e.isPending).toList(growable: false);

  /// 把多门课的结果拼起来，未交的排前面，其余按课程顺序。
  static HomeworkList merge(List<HomeworkList> lists) {
    final List<HomeworkItem> all = <HomeworkItem>[
      for (final HomeworkList l in lists) ...l.items,
    ];
    all.sort((HomeworkItem a, HomeworkItem b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return 0;
    });
    return HomeworkList(
      items: all,
      failures: <String>[
        for (final HomeworkList l in lists) ...l.failures,
      ],
    );
  }
}
