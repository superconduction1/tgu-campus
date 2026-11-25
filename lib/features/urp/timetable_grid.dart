import 'models.dart';

/// 课表网格里的一格（可能跨多节）。
class GridEntry {
  const GridEntry({
    required this.course,
    required this.day,
    required this.startSession,
    required this.sessionCount,
    required this.place,
  });

  final CourseInfo course;

  /// 星期几，1 = 周一。
  final int day;

  /// 起始节次，1 = 第一节。
  final int startSession;

  /// 连堂节数。
  final int sessionCount;

  final CourseTimePlace place;

  int get endSession => startSession + sessionCount - 1;

  @override
  String toString() => 'GridEntry(${course.name} 周$day 第$startSession-${endSession}节)';
}

/// 某一周的课表布局。
///
/// 纯 Dart，不依赖 Flutter，所以能直接跑测试——排版算错比画错更难看。
class TimetableGrid {
  const TimetableGrid({
    required this.week,
    required this.maxSession,
    required this.entries,
  });

  final int week;

  /// 这天最多上到第几节（决定网格高度）。
  final int maxSession;

  final List<GridEntry> entries;

  static const List<String> weekdayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

  /// 从课表数据里取出第 [week] 周的布局。
  static TimetableGrid build(Timetable timetable, {required int week}) {
    final List<GridEntry> entries = <GridEntry>[];
    int maxSession = 12;

    for (final CourseInfo course in timetable.courses) {
      for (final CourseTimePlace place in course.timePlaces) {
        if (place.classDay < 1 || place.classDay > 7) continue;
        if (place.startSession < 1) continue;
        // 没有周次信息时不做过滤，宁可多显示也不要漏课
        if (place.weekPattern.isNotEmpty && !place.isActiveInWeek(week)) {
          continue;
        }
        entries.add(
          GridEntry(
            course: course,
            day: place.classDay,
            startSession: place.startSession,
            sessionCount: place.sessionCount < 1 ? 1 : place.sessionCount,
            place: place,
          ),
        );
        if (place.startSession + place.sessionCount - 1 > maxSession) {
          maxSession = place.startSession + place.sessionCount - 1;
        }
      }
    }

    entries.sort((GridEntry a, GridEntry b) {
      final int byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.startSession.compareTo(b.startSession);
    });

    return TimetableGrid(week: week, maxSession: maxSession, entries: entries);
  }

  bool get isEmpty => entries.isEmpty;

  /// 第 [day] 天第 [session] 节对应的课，没有则返回 null。
  GridEntry? cellAt(int day, int session) {
    for (final GridEntry entry in entries) {
      if (entry.day == day &&
          session >= entry.startSession &&
          session <= entry.endSession) {
        return entry;
      }
    }
    return null;
  }

  /// 同一天里同一时间是否已经被别的课占了——用于发现冲突。
  static List<GridEntry> conflicts(TimetableGrid grid) {
    final List<GridEntry> bad = <GridEntry>[];
    for (final GridEntry a in grid.entries) {
      for (final GridEntry b in grid.entries) {
        if (identical(a, b)) continue;
        if (a.day != b.day) continue;
        final bool overlap =
            a.startSession <= b.endSession && b.startSession <= a.endSession;
        if (overlap && !bad.contains(a)) bad.add(a);
      }
    }
    return bad;
  }
}
