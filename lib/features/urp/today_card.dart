import 'package:flutter/material.dart';

import 'models.dart';
import 'today.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 首页顶部的「今天上什么课」。
///
/// 自己拉学期条和课表，失败时只显示一行提示，不打扰首页其他功能。
class TodayCard extends StatefulWidget {
  const TodayCard({super.key, required this.api});

  final UrpApi api;

  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
  late Future<TodaySchedule> _future = _load();

  Future<TodaySchedule> _load() async {
    final TermInfo term = await widget.api.fetchTermInfo();
    final Timetable timetable = await widget.api.fetchTimetable();
    return buildTodaySchedule(timetable, term);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TodaySchedule>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<TodaySchedule> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Shell(child: _LoadingRow());
        }
        if (snapshot.hasError) {
          final bool expired = snapshot.error is UrpSessionExpiredException;
          return _Shell(
            child: Row(
              children: <Widget>[
                Icon(
                  expired ? Icons.lock_clock_outlined : Icons.cloud_off_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(expired ? '教务登录已过期' : '今天的课没取到'),
                ),
                if (expired)
                  TextButton(
                    onPressed: () => urpRelogin(context, widget.api),
                    child: const Text('重新登录'),
                  )
                else
                  TextButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          );
        }
        return _Shell(child: _TodayBody(schedule: snapshot.data!, onRefresh: _reload));
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: child,
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text('正在取今天的课…',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({required this.schedule, required this.onRefresh});

  final TodaySchedule schedule;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('今天 · 周${schedule.weekdayLabel}',
                style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('第${schedule.week}周',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.outline)),
            const Spacer(),
            IconButton(
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (schedule.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('今天没课',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.outline)),
          )
        else
          for (final TodayClass item in schedule.classes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 92,
                    child: Text(
                      item.timeRange.isEmpty ? item.sessionLabel : item.timeRange,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures()
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(item.name, style: theme.textTheme.bodyMedium),
                        if (item.room.isNotEmpty || item.teacher.isNotEmpty)
                          Text(
                            <String>[
                              if (item.room.isNotEmpty) item.room,
                              if (item.teacher.isNotEmpty) item.teacher,
                            ].join(' · '),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
