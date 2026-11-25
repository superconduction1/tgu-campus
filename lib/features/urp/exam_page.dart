import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_cache.dart';
import '../../core/design.dart';
import '../../core/disk_cache.dart';
import '../../core/snapshot.dart';
import 'models.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 考试安排页。
class ExamPage extends StatefulWidget {
  const ExamPage({super.key, required this.api, this.cache});

  final UrpApi api;

  /// 离线缓存放哪儿；测试里可以塞一个临时目录。
  final DiskCache? cache;

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamData {
  const _ExamData(this.exams, {this.cachedAt});

  final List<ExamRecord> exams;
  final DateTime? cachedAt;
}

class _ExamPageState extends State<ExamPage> {
  late final DiskCache _cache = widget.cache ?? appCache();
  late Future<_ExamData> _future = _load();

  /// 先打网络，失败退回上次存下来的整页 HTML 重新解析。
  Future<_ExamData> _load() async {
    try {
      final String source = await widget.api.fetchExamsSource();
      final List<ExamRecord> exams = widget.api.examsFromSource(source);
      unawaited(_cache.save(CacheKeys.exams, source));
      return _ExamData(exams);
    } catch (_) {
      final CachedSnapshot? saved = await _cache.load(CacheKeys.exams);
      if (saved != null) {
        try {
          final List<ExamRecord> stale =
              widget.api.examsFromSource(saved.value);
          if (stale.isNotEmpty) {
            return _ExamData(stale, cachedAt: saved.savedAt);
          }
        } catch (_) {
          // 缓存坏了就当没有
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
        title: const Text('考试'),
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
      body: FutureBuilder<_ExamData>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<_ExamData> snapshot,
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

          final _ExamData data =
              snapshot.data ?? const _ExamData(<ExamRecord>[]);
          final List<ExamRecord> exams = data.exams;
          if (exams.isEmpty) {
            return const UrpEmptyView(
              icon: Icons.event_available_outlined,
              title: '还没有考试安排',
              detail: '教务处排考后会出现在这里。',
            );
          }

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
              _ExamSummary(count: exams.length, cached: data.cachedAt != null),
              const SectionTitle('考试安排'),
              for (final ExamRecord exam in exams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExamCard(record: exam),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExamSummary extends StatelessWidget {
  const _ExamSummary({required this.count, required this.cached});

  final int count;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: TguColors.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.school_outlined,
              size: 17,
              color: TguColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '本学期考试',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: TguColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '共 $count 场',
                style: const TextStyle(fontSize: 12, color: TguColors.sub),
              ),
            ],
          ),
          const Spacer(),
          if (cached) const SoftBadge('离线', color: Color(0xFFF2994A)),
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.record});

  final ExamRecord record;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];

    void addRow(IconData icon, String text) {
      if (text.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 15, color: TguColors.sub),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: TguColors.ink,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    addRow(Icons.schedule_outlined, record.examTime);
    addRow(Icons.place_outlined, record.location);
    addRow(Icons.event_seat_outlined, record.seatNo);
    addRow(Icons.confirmation_number_outlined, record.ticketNo);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: TguColors.accentFor(record.courseName),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        record.courseName,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: TguColors.ink,
                        ),
                      ),
                    ),
                    if (record.examType.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      SoftBadge(record.examType),
                    ],
                  ],
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text(
                      '教务处还没公布具体时间地点',
                      style: TextStyle(fontSize: 12.5, color: TguColors.sub),
                    ),
                  )
                else
                  ...rows,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
