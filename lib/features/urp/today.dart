import 'models.dart';
import 'timetable_grid.dart';

/// 今天的一节课。比课表网格里的 [GridEntry] 更贴近「一眼要看什么」：
/// 几点上、在哪、上几节。
class TodayClass {
  const TodayClass({
    required this.name,
    required this.room,
    required this.teacher,
    required this.startSession,
    required this.sessionCount,
    required this.timeRange,
    required this.weeks,
  });

  final String name;
  final String room;
  final String teacher;
  final int startSession;
  final int sessionCount;

  /// 形如 `08:20-09:55`。作息表里查不到对应节次时是空串。
  final String timeRange;

  /// 教务原文的周次说明，如 `4-15周`。
  final String weeks;

  int get endSession => startSession + sessionCount - 1;

  String get sessionLabel => '第$startSession-$endSession节';

  @override
  String toString() => 'TodayClass($name $timeRange $room)';
}

/// 某一天要上的课。
class TodaySchedule {
  const TodaySchedule({
    required this.weekday,
    required this.week,
    required this.classes,
  });

  /// 1 = 周一。
  final int weekday;

  /// 教学周。
  final int week;

  final List<TodayClass> classes;

  bool get isEmpty => classes.isEmpty;

  /// `一`..`日`。
  String get weekdayLabel => weekday >= 1 && weekday <= 7
      ? TimetableGrid.weekdayLabels[weekday - 1]
      : '?';
}

/// 从整张课表里挑出 [term] 那一天、那一周的课。
///
/// 直接复用 [TimetableGrid.build] 的周次过滤，保证和课表页看到的完全一致
/// （同一个 `classWeek` 位串、同一套连堂规则），不另写一套判断。
TodaySchedule buildTodaySchedule(Timetable timetable, TermInfo term) {
  final Map<int, SectionTime> byIndex = <int, SectionTime>{
    for (final SectionTime s in timetable.sections) s.index: s,
  };

  final TimetableGrid grid = TimetableGrid.build(timetable, week: term.week);
  final List<GridEntry> today = grid.entries
      .where((GridEntry e) => e.day == term.weekday)
      .toList()
    ..sort((GridEntry a, GridEntry b) =>
        a.startSession.compareTo(b.startSession));

  final List<TodayClass> classes = <TodayClass>[];
  for (final GridEntry entry in today) {
    final int last = entry.startSession + entry.sessionCount - 1;
    final SectionTime? first = byIndex[entry.startSession];
    final SectionTime? end = byIndex[last];
    final String range = (first == null || end == null)
        ? ''
        : '${first.startLabel}-${end.endLabel}';
    classes.add(TodayClass(
      name: entry.course.name,
      room: entry.place.placeLabel,
      teacher: entry.course.teacher,
      startSession: entry.startSession,
      sessionCount: entry.sessionCount,
      timeRange: range,
      weeks: entry.course.weeks,
    ));
  }

  return TodaySchedule(
    weekday: term.weekday,
    week: term.week,
    classes: classes,
  );
}
