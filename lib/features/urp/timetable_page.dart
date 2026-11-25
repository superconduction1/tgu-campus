import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_cache.dart';
import '../../core/design.dart';
import '../../core/disk_cache.dart';
import '../../core/snapshot.dart';
import 'models.dart';
import 'timetable_grid.dart';
import 'urp_api.dart';
import 'urp_parser.dart';
import 'urp_widgets.dart';

/// 周课表。
///
/// 排版逻辑全在 [TimetableGrid]（纯 Dart，有测试），这里只负责画。
/// 网络拿不到时会退回上次成功的本地快照，并在顶上标明数据时间。
class TimetablePage extends StatefulWidget {
  const TimetablePage({
    super.key,
    required this.api,
    this.initialWeek = 1,
    this.cache,
  });

  final UrpApi api;
  final int initialWeek;

  /// 传 null 用 App 的默认缓存目录；测试里可以塞临时目录。
  final DiskCache? cache;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late int _week = widget.initialWeek;
  late final DiskCache _cache = widget.cache ?? appCache();
  late Future<_Loaded> _future = _load();

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

  /// 先走网络；网络不通再退回上次成功存下来的快照。
  ///
  /// 两边都没有就把异常抛出去，让页面显示原来的错误页
  /// （会话过期要能弹「重新登录」，不能被缓存掩掉）。
  Future<_Loaded> _load() async {
    try {
      final Timetable fresh = await widget.api.fetchTimetable();
      unawaited(_cache.save(
        CacheKeys.timetable,
        jsonEncode(fresh.raw),
      ));
      return _Loaded(timetable: fresh);
    } catch (error) {
      final CachedSnapshot? snapshot = await _cache.load(CacheKeys.timetable);
      if (snapshot != null) {
        try {
          final Timetable stale =
              UrpParser.parseTimetableJson(jsonDecode(snapshot.value));
          if (!stale.isEmpty) {
            return _Loaded(timetable: stale, cachedAt: snapshot.savedAt);
          }
        } catch (_) {
          // 缓存的 JSON 坏了就当没有。
        }
      }
      rethrow;
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
    _loadTerm();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TguColors.page,
      appBar: AppBar(
        title: const Text('课表'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            color: TguColors.sub,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_Loaded> snapshot) {
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

          final _Loaded loaded = snapshot.data!;
          final Timetable timetable = loaded.timetable;
          if (timetable.isEmpty) {
            return const Center(child: Text('本学期还没有排课'));
          }

          final TimetableGrid grid = TimetableGrid.build(timetable, week: _week);

          return Column(
            children: <Widget>[
              if (loaded.cachedAt != null)
                UrpStaleBanner(label: cachedLabel(loaded.cachedAt!), onRetry: _reload),
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

/// 一次加载的结果：正常是网络数据，[cachedAt] 非空表示用的是本地快照。
class _Loaded {
  const _Loaded({required this.timetable, this.cachedAt});

  final Timetable timetable;
  final DateTime? cachedAt;
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
    final bool isCurrent = currentWeek == week;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: TguColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TguColors.line),
        ),
        child: Row(
          children: <Widget>[
            _ArrowButton(
              icon: Icons.chevron_left,
              onTap: week > 1 ? () => onChanged(week - 1) : null,
            ),
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '第 $week 周',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TguColors.ink,
                      ),
                    ),
                    if (isCurrent) ...<Widget>[
                      const SizedBox(width: 6),
                      const SoftBadge('本周', color: TguColors.brand),
                    ],
                  ],
                ),
              ),
            ),
            _ArrowButton(
              icon: Icons.chevron_right,
              onTap: week < 30 ? () => onChanged(week + 1) : null,
            ),
            if (currentWeek != null && !isCurrent)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(currentWeek!),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: TguColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text(
                      '回本周',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TguColors.brand,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 周次条两端的箭头，禁用了就变浅。
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 44,
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? TguColors.line : TguColors.sub,
        ),
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
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: <Widget>[
          Text(
            '本周 $courses 门课 · 共 ${grid.entries.length} 段',
            style: const TextStyle(fontSize: 12, color: TguColors.sub),
          ),
          const Spacer(),
          Text(
            '总 ${timetable.totalCredits.toStringAsFixed(1)} 学分',
            style: const TextStyle(fontSize: 12, color: TguColors.sub),
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

  Color _colorFor(String code) => TguColors.accentFor(code);

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
