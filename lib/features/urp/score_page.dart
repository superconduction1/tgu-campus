import 'package:flutter/material.dart';

import 'models.dart';
import 'score_stats.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 成绩页：按学期分组，顶部给汇总。
class ScorePage extends StatefulWidget {
  const ScorePage({super.key, required this.api});

  final UrpApi api;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  late Future<List<ScoreRecord>> _future = widget.api.fetchScores();

  void _reload() {
    setState(() {
      _future = widget.api.fetchScores();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<ScoreRecord>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<ScoreRecord>> snapshot,
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

          final List<ScoreRecord> records =
              snapshot.data ?? const <ScoreRecord>[];
          if (records.isEmpty) {
            return const UrpEmptyView(
              icon: Icons.grading_outlined,
              title: '还没有成绩',
              detail: '本学期课程还没结课。等出分后这里会自动显示，不用做别的。',
            );
          }

          final List<TermScores> groups = ScoreStats.groupByTerm(records);
          final List<Widget> children = <Widget>[
            _Overview(records: records),
          ];
          for (final TermScores group in groups) {
            children.add(_TermHeader(group: group));
            for (final ScoreRecord record in group.records) {
              children.add(_ScoreTile(record: record));
            }
          }
          children.add(const SizedBox(height: 24));

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            children: children,
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

class _Overview extends StatelessWidget {
  const _Overview({required this.records});

  final List<ScoreRecord> records;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double credits = ScoreStats.totalCredits(records);
    final double? average = ScoreStats.weightedAverage(records);
    final int failed = ScoreStats.failedCount(records);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _Stat(label: '门数', value: '${records.length}'),
          _Stat(label: '已修学分', value: _trim(credits, 2)),
          _Stat(
            label: '加权平均',
            value: average == null ? '—' : average.toStringAsFixed(1),
          ),
          _Stat(
            label: '不及格',
            value: '$failed',
            danger: failed > 0,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: danger ? scheme.error : null,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }
}

class _TermHeader extends StatelessWidget {
  const _TermHeader({required this.group});

  final TermScores group;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? average = group.average;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              group.term,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            <String>[
              if (group.credits > 0) '${_trim(group.credits, 2)} 学分',
              if (average != null) '均分 ${average.toStringAsFixed(1)}',
            ].join(' · '),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.record});

  final ScoreRecord record;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool passed = record.isPassed;
    final String meta = <String>[
      if (record.courseType.isNotEmpty) record.courseType,
      if (record.credit.isNotEmpty) '${record.credit} 学分',
      if (record.gpa.isNotEmpty) '绩点 ${record.gpa}',
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(record.courseName),
      subtitle: meta.isEmpty ? null : Text(meta),
      trailing: Text(
        record.score.isEmpty ? '—' : record.score,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: passed ? scheme.primary : scheme.error,
            ),
      ),
    );
  }
}
