import 'package:flutter/material.dart';

import '../../core/design.dart';
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
                  color: TguColors.sub,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    expired ? '教务登录已过期' : '今天的课没取到',
                    style: const TextStyle(fontSize: 13.5, color: TguColors.ink),
                  ),
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
        return _Shell(
          child: _TodayBody(schedule: snapshot.data!, onRefresh: _reload),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: child,
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text(
          '正在取今天的课…',
          style: TextStyle(fontSize: 13, color: TguColors.sub),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '今天',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: TguColors.ink,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: TguColors.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '周${schedule.weekdayLabel} · 第${schedule.week}周',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: TguColors.brand,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              onPressed: onRefresh,
              icon: const Icon(
                Icons.refresh,
                size: 17,
                color: TguColors.sub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (schedule.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '今天没课',
              style: TextStyle(fontSize: 13.5, color: TguColors.sub),
            ),
          )
        else
          for (final TodayClass item in schedule.classes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 86,
                    child: Text(
                      item.timeRange.isEmpty
                          ? item.sessionLabel
                          : item.timeRange,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: TguColors.brand,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: TguColors.ink,
                          ),
                        ),
                        if (item.room.isNotEmpty || item.teacher.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              <String>[
                                if (item.room.isNotEmpty) item.room,
                                if (item.teacher.isNotEmpty) item.teacher,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: TguColors.sub,
                              ),
                            ),
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
