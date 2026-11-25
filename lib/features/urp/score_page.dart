import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_cache.dart';
import '../../core/design.dart';
import '../../core/disk_cache.dart';
import '../../core/snapshot.dart';
import 'models.dart';
import 'score_stats.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 成绩页：学期分段切换 + 汇总数字 + 课程清单。
class ScorePage extends StatefulWidget {
  const ScorePage({super.key, required this.api, this.cache});

  final UrpApi api;

  /// 离线缓存放哪儿；测试里可以塞一个临时目录。
  final DiskCache? cache;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

/// 一次加载的结果：数据 + 是不是缓存（缓存带时间）。
class _ScoreData {
  const _ScoreData(this.records, {this.cachedAt});

  final List<ScoreRecord> records;
  final DateTime? cachedAt;
}

class _ScorePageState extends State<ScorePage> {
  late final DiskCache _cache = widget.cache ?? appCache();
  late Future<_ScoreData> _future = _load();

  /// 0 表示「全部学期」，其余对应 groups[selected - 1]。
  int _selected = 0;

  /// 先打网络；失败就退回上次存下来的原文重新解析。
  Future<_ScoreData> _load() async {
    try {
      final String source = await widget.api.fetchScoresSource();
      final List<ScoreRecord> records = widget.api.scoresFromSource(source);
      unawaited(_cache.save(CacheKeys.scores, source));
      return _ScoreData(records);
    } catch (_) {
      final CachedSnapshot? saved = await _cache.load(CacheKeys.scores);
      if (saved != null) {
        try {
          final List<ScoreRecord> stale =
              widget.api.scoresFromSource(saved.value);
          if (stale.isNotEmpty) {
            return _ScoreData(stale, cachedAt: saved.savedAt);
          }
        } catch (_) {
          // 缓存解析不了就当没有
        }
      }
      rethrow;
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TguColors.page,
      appBar: AppBar(
        title: const Text('成绩'),
        backgroundColor: TguColors.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_ScoreData>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<_ScoreData> snapshot,
        ) {
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

          final _ScoreData data =
              snapshot.data ?? const _ScoreData(<ScoreRecord>[]);
          final List<ScoreRecord> records = data.records;
          if (records.isEmpty) {
            return const UrpEmptyView(
              icon: Icons.grading_outlined,
              title: '还没有成绩',
              detail: '本学期课程还没结课。等出分后这里会自动显示，不用做别的。',
            );
          }

          final List<TermScores> groups = ScoreStats.groupByTerm(records);
          final int selected = _selected.clamp(0, groups.length);
          final List<ScoreRecord> visible = selected == 0
              ? records
              : groups[selected - 1].records;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: <Widget>[
              if (data.cachedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: UrpStaleBanner(
                    label: cachedLabel(data.cachedAt!),
                    onRetry: _reload,
                  ),
                ),
              _SummaryCard(
                records: visible,
                total: records.length,
                groups: groups,
                selected: selected,
                onSelected: (int index) => setState(() => _selected = index),
                stale: data.cachedAt != null,
              ),
              const SectionTitle('课程明细'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < visible.length; i++) ...<Widget>[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 14,
                          endIndent: 14,
                          color: TguColors.line,
                        ),
                      _ScoreRow(record: visible[i]),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _trim(double value, int digits) {
  final String text = value.toStringAsFixed(digits);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.records,
    required this.total,
    required this.groups,
    required this.selected,
    required this.onSelected,
    required this.stale,
  });

  final List<ScoreRecord> records;
  final int total;
  final List<TermScores> groups;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final double credits = ScoreStats.totalCredits(records);
    final double? average = ScoreStats.weightedAverage(records);
    final int failed = ScoreStats.failedCount(records);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: TguColors.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.emoji_events_outlined,
                  size: 17,
                  color: TguColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '成绩',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TguColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$total 门',
                style: const TextStyle(fontSize: 12, color: TguColors.sub),
              ),
              const Spacer(),
              if (stale)
                const SoftBadge('离线', color: Color(0xFFF2994A)),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: StatGrid(
              items: <StatItem>[
                StatItem(
                  average == null ? '—' : average.toStringAsFixed(1),
                  '加权均分',
                ),
                StatItem(_trim(credits, 2), '学分'),
                StatItem('${records.length}', '门数'),
                StatItem(
                  '$failed',
                  '不及格',
                  danger: failed > 0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (groups.length > 1)
            Transform.translate(
              offset: const Offset(-16, 0),
              child: PillTabs(
                items: <String>[
                  '全部',
                  for (final TermScores group in groups) group.term,
                ],
                selectedIndex: selected,
                onChanged: onSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.record});

  final ScoreRecord record;

  @override
  Widget build(BuildContext context) {
    final bool passed = record.isPassed;
    final String meta = <String>[
      if (record.courseType.isNotEmpty) record.courseType,
      if (record.credit.isNotEmpty) '${record.credit} 学分',
      if (record.gpa.isNotEmpty) '绩点 ${record.gpa}',
    ].join(' · ');

    return AccentTile(
      accent: TguColors.accentFor(record.courseName),
      title: record.courseName,
      meta: meta,
      trailing: Text(
        record.score.isEmpty ? '—' : record.score,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: passed ? TguColors.ink : const Color(0xFFD93A3A),
        ),
      ),
    );
  }
}
