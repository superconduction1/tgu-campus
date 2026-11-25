import 'package:flutter/material.dart';

import 'models.dart';
import 'timetable_grid.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 周课表。
///
/// 排版逻辑全在 [TimetableGrid]（纯 Dart，有测试），这里只负责画。
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.api, this.initialWeek = 1});

  final UrpApi api;
  final int initialWeek;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late int _week = widget.initialWeek;
  late Future<Timetable> _future = widget.api.fetchTimetable();

  /// 教务说的「现在第几周」。拿不到就是 null，界面退化成只能手翻。
  int? _currentWeek;

  /// 用户自己翻过周次没有。翻过了就别再被服务器周次覆盖。
  bool _weekTouched = false;

  @override
  void initState() {
    super.initState();
    _loadTerm();
  }

  Future<void> _loadTerm() async {
    try {
      final TermInfo info = await widget.api.fetchTermInfo();
      if (!mounted) return;
      final int raw = info.week;
      final int week = raw < 1 ? 1 : (raw > 30 ? 30 : raw);
      setState(() {
        _currentWeek = week;
        if (!_weekTouched) _week = week;
      });
    } catch (_) {
      // 学期条拿不到不影响课表本身，停在默认周就好
    }
  }

  void _setWeek(int value) {
    setState(() {
      _week = value;
      _weekTouched = true;
    });
  }

  void _reload() {
    setState(() {
      _future = widget.api.fetchTimetable();
    });
    _loadTerm();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Timetable>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<Timetable> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return UrpErrorView(
              error: snapshot.error!,
              onRetry: _reload,
              onRelogin: () => urpRelogin(context, widget.api),
            );
          }

          final Timetable timetable = snapshot.data!;
          if (timetable.isEmpty) {
            return const Center(child: Text('本学期还没有排课'));
          }

          final TimetableGrid grid = TimetableGrid.build(timetable, week: _week);

          return Column(
            children: <Widget>[
              _WeekBar(
                week: _week,
                currentWeek: _currentWeek,
                onChanged: _setWeek,
              ),
              _SummaryBar(timetable: timetable, grid: grid),
              Expanded(
                child: _Grid(grid: grid, sections: timetable.sections),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.onChanged,
    this.currentWeek,
  });

  final int week;
  final ValueChanged<int> onChanged;
  final int? currentWeek;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: scheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            onPressed: week > 1 ? () => onChanged(week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '第 $week 周',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            onPressed: week < 30 ? () => onChanged(week + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          if (currentWeek != null && currentWeek != week)
            TextButton(
              onPressed: () => onChanged(currentWeek!),
              child: const Text('本周'),
            ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.timetable, required this.grid});

  final Timetable timetable;
  final TimetableGrid grid;

  @override
  Widget build(BuildContext context) {
    final int courses =
        grid.entries.map((GridEntry e) => e.course.code).toSet().length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Text(
            '本周 $courses 门课 · 共 ${grid.entries.length} 段',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Text(
            '总 ${timetable.totalCredits.toStringAsFixed(1)} 学分',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.grid, required this.sections});

  final TimetableGrid grid;
  final List<SectionTime> sections;

  static const double _headerHeight = 34;
  static const double _rowHeight = 58;
  static const double _timeColumnWidth = 46;

  String _timeLabel(int session) {
    for (final SectionTime s in sections) {
      if (s.index == session) return '${s.startLabel}\n${s.endLabel}';
    }
    return '';
  }

  Color _colorFor(String code) {
    final List<Color> palette = <Color>[
      const Color(0xFF71246B),
      const Color(0xFF2A5082),
      const Color(0xFF1F7A5A),
      const Color(0xFF8A5A00),
      const Color(0xFF7A2A2A),
      const Color(0xFF3F5C8A),
      const Color(0xFF5B3A8A),
    ];
    return palette[code.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int rows = grid.maxSession;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double dayWidth =
            (constraints.maxWidth - _timeColumnWidth) / TimetableGrid.weekdayLabels.length;

        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: _headerHeight + rows * _rowHeight,
            child: Stack(
              children: <Widget>[
                // 星期表头
                for (int day = 1; day <= 7; day++)
                  Positioned(
                    left: _timeColumnWidth + (day - 1) * dayWidth,
                    top: 0,
                    width: dayWidth,
                    height: _headerHeight,
                    child: Center(
                      child: Text(
                        TimetableGrid.weekdayLabels[day - 1],
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                // 行分隔线与节次时间
                for (int row = 1; row <= rows; row++) ...<Widget>[
                  Positioned(
                    left: 0,
                    top: _headerHeight + (row - 1) * _rowHeight,
                    width: constraints.maxWidth,
                    height: 1,
                    child: ColoredBox(color: scheme.outlineVariant),
                  ),
                  Positioned(
                    left: 0,
                    top: _headerHeight + (row - 1) * _rowHeight,
                    width: _timeColumnWidth,
                    height: _rowHeight,
                    child: Center(
                      child: Text(
                        _timeLabel(row).isEmpty ? '$row' : '$row\n${_timeLabel(row)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
                // 课程块
                for (final GridEntry entry in grid.entries)
                  Positioned(
                    left: _timeColumnWidth + (entry.day - 1) * dayWidth + 1,
                    top: _headerHeight +
                        (entry.startSession - 1) * _rowHeight +
                        1,
                    width: dayWidth - 2,
                    height: entry.sessionCount * _rowHeight - 3,
                    child: _CourseBlock(entry: entry, color: _colorFor(entry.course.code)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.entry, required this.color});

  final GridEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showDetail(context),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.course.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                entry.place.room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(entry.course.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _line('教师', entry.course.teacher),
            _line('时间', '周${TimetableGrid.weekdayLabels[entry.day - 1]} '
                '第 ${entry.startSession}-${entry.endSession} 节'),
            _line('地点', '${entry.place.campus} ${entry.place.placeLabel}'),
            _line('周次', entry.place.weekDescription),
            _line('学分', entry.course.credit),
            _line('属性', entry.course.attribute),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
