/// URP 教务各模块的数据模型。
///
/// 字段名尽量贴近学校页面上的列名，减少映射时的认知负担。
library;

class ScoreRecord {
  const ScoreRecord({
    required this.courseName,
    this.courseCode = '',
    this.courseType = '',
    this.credit = '',
    this.score = '',
    this.gpa = '',
    this.term = '',
    this.examType = '',
  });

  final String courseName;
  final String courseCode;

  /// 课程性质 / 课程属性，如「必修」「选修」。
  final String courseType;

  /// 学分，保留原始字符串（可能是「3.0」或「3」）。
  final String credit;

  /// 成绩原始值（可能是数字，也可能是「优秀」「合格」）。
  final String score;

  /// 绩点。
  final String gpa;

  /// 学期，如「2025-2026-1」。
  final String term;

  final String examType;

  /// 成绩能否解析成数字，用于算加权平均分。
  double? get numericScore => double.tryParse(score.replaceAll(RegExp(r'[^\d.]'), ''));

  double? get numericCredit => double.tryParse(credit.replaceAll(RegExp(r'[^\d.]'), ''));

  bool get isPassed {
    final double? value = numericScore;
    if (value != null) return value >= 60;
    return score.contains('合格') || score.contains('通过') || score.contains('优秀');
  }

  @override
  String toString() => 'ScoreRecord($courseName, $score, $credit)';
}

class ExamRecord {
  const ExamRecord({
    required this.courseName,
    this.examTime = '',
    this.location = '',
    this.seatNo = '',
    this.examType = '',
    this.ticketNo = '',
  });

  final String courseName;

  /// 考试时间原始字符串，格式由学校决定，未做解析。
  final String examTime;

  final String location;
  final String seatNo;
  final String examType;
  final String ticketNo;

  @override
  String toString() => 'ExamRecord($courseName, $examTime, $location)';
}

/// 一门课（课表用）。
///
/// 字段来自 `ajaxStudentSchedule/callback` 返回的 `xkxx`：
/// `kch` 课程号、`kxh` 课序号、`kcm` 课程名、`xf` 学分、`kcsx` 课程属性、
/// `kclb` 课程类别、`js` 教师、`xdfs` 修读方式、`xkzt` 选课状态、`xkxz` 选课性质。
class CourseInfo {
  const CourseInfo({
    required this.code,
    required this.name,
    this.classSequence = '',
    this.teacher = '',
    this.credit = '',
    this.attribute = '',
    this.category = '',
    this.studyMode = '',
    this.selectState = '',
    this.weeks = '',
    this.timePlaces = const <CourseTimePlace>[],
  });

  final String code;
  final String name;

  /// 课序号。
  final String classSequence;

  final String teacher;
  final String credit;

  /// 课程属性（必修/选修）。
  final String attribute;

  /// 课程类别。
  final String category;

  /// 修读方式。
  final String studyMode;

  /// 选课状态。
  final String selectState;

  /// 上课周次描述，如「4-15周;5-20周单周」。
  final String weeks;

  /// 上课时间地点，一门课可能有多段。
  final List<CourseTimePlace> timePlaces;

  @override
  String toString() => 'CourseInfo($name, $teacher)';
}

/// 一段上课时间与地点。
///
/// 来自 `timeAndPlaceList` 的实测结构：
/// `classDay` 星期（1=周一）、`classSessions` 起始节次、
/// `continuingSession` 连堂节数、`classWeek` 是 24 位 0/1 串表示第几周上课、
/// `weekDescription` 是人类可读的「4-15周」。
class CourseTimePlace {
  const CourseTimePlace({
    required this.classDay,
    required this.startSession,
    required this.sessionCount,
    this.campus = '',
    this.building = '',
    this.room = '',
    this.weekPattern = '',
    this.weekDescription = '',
  });

  final int classDay;
  final int startSession;
  final int sessionCount;
  final String campus;
  final String building;
  final String room;
  final String weekPattern;
  final String weekDescription;

  /// 第 [week] 周（从 1 开始）是否要上这门课。
  bool isActiveInWeek(int week) =>
      week >= 1 && week <= weekPattern.length && weekPattern[week - 1] == '1';

  String get placeLabel => '$building$room';

  @override
  String toString() => 'CourseTimePlace(周$classDay 第$startSession节 $placeLabel)';
}

/// 节次作息时间，来自 `jcsjbs`：`{"jc":"1","kssj":"0820","jssj":"0905"}`。
class SectionTime {
  const SectionTime({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;

  /// 形如 `0820`。
  final String start;

  /// 形如 `0905`。
  final String end;

  /// 格式化成 `08:20`。
  String get startLabel => _pretty(start);

  String get endLabel => _pretty(end);

  static String _pretty(String raw) => raw.length == 4
      ? '${raw.substring(0, 2)}:${raw.substring(2)}'
      : raw;
}

/// 课表数据。
///
/// `ajaxStudentSchedule/callback` 返回的完整结构里，
/// 除课程外还有 `dateList` / `allUnits` / `csz` / `rwbgLists`，
/// 用于渲染周课表网格，这里先原样保留，等界面部分再解析。
class Timetable {
  const Timetable({
    required this.courses,
    this.totalCredits = 0,
    this.sections = const <SectionTime>[],
    this.raw = const <String, dynamic>{},
  });

  final List<CourseInfo> courses;

  /// 本学期总学分，来自 `allUnits`（实测是数字，如 26.75）。
  final double totalCredits;

  /// 节次作息表，来自 `jcsjbs`。
  final List<SectionTime> sections;

  /// 原始 JSON，界面需要细节时用。
  final Map<String, dynamic> raw;

  bool get isEmpty => courses.isEmpty;

  /// 按星期几取课程（1=周一）。
  List<CourseInfo> coursesOn(int day) => courses
      .where((CourseInfo c) =>
          c.timePlaces.any((CourseTimePlace p) => p.classDay == day))
      .toList();
}

/// 待办从哪来。将来学习通作业也接进同一个列表。
enum TodoKind {
  /// 学分/学费确认。
  creditConfirm,

  /// 学业预警。
  warning,

  /// 学习通作业（未接入）。
  homework,

  other,
}

/// 一条待办。
class TodoItem {
  const TodoItem({
    required this.title,
    this.detail = '',
    this.kind = TodoKind.other,
    this.path = '',
  });

  final String title;
  final String detail;
  final TodoKind kind;

  /// 对应的教务页面路径，点开时用。
  final String path;

  @override
  String toString() => 'TodoItem($title)';
}

/// 教务页面顶部那条学期信息：`2026-2027 秋 第13周 星期三`。
///
/// 它出现在**每个登录后的页面**里（`<span class="span_bbzx">`），
/// 所以「现在第几周」不用另外去抓校历页。
class TermInfo {
  const TermInfo({
    required this.year,
    required this.term,
    required this.week,
    required this.weekday,
    this.raw = '',
  });

  /// 学年，形如 `2026-2027`。
  final String year;

  /// 学期：`秋` / `春` / `夏`。
  final String term;

  /// 教学周，从 1 开始。
  final int week;

  /// 星期几，1=周一；0 表示没解析到。
  final int weekday;

  /// 原始文本，排查时看。
  final String raw;

  static const List<String> weekdayNames = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  String get label => <String>[year, term, '第$week周']
      .where((String s) => s.isNotEmpty)
      .join(' ');
}

class ScoreSummary {
  const ScoreSummary({
    required this.records,
    required this.weightedAverage,
    required this.totalCredits,
  });

  final List<ScoreRecord> records;

  /// 按学分加权的平均分；没有可用数据时为 null。
  final double? weightedAverage;

  final double totalCredits;

  static ScoreSummary from(List<ScoreRecord> records) {
    double creditSum = 0;
    double weighted = 0;
    for (final ScoreRecord record in records) {
      final double? credit = record.numericCredit;
      final double? score = record.numericScore;
      if (credit == null || score == null) continue;
      creditSum += credit;
      weighted += credit * score;
    }
    return ScoreSummary(
      records: records,
      weightedAverage: creditSum > 0 ? weighted / creditSum : null,
      totalCredits: creditSum,
    );
  }
}
