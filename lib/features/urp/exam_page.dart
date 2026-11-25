import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_cache.dart';
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
      appBar: AppBar(
        title: const Text('考试'),
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

          return Column(
            children: <Widget>[
              if (data.cachedAt != null)
                UrpStaleBanner(
                  label: cachedLabel(data.cachedAt!),
                  onRetry: _reload,
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: exams.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) =>
                      _ExamCard(record: exams[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.record});

  final ExamRecord record;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Widget> rows = <Widget>[];

    void addRow(IconData icon, String text) {
      if (text.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 15, color: scheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ));
    }

    addRow(Icons.schedule_outlined, record.examTime);
    addRow(Icons.place_outlined, record.location);
    addRow(Icons.event_seat_outlined, record.seatNo);
    addRow(Icons.confirmation_number_outlined, record.ticketNo);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  record.courseName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (record.examType.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    record.examType,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '教务处还没公布具体时间地点',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}
