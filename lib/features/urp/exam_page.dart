import 'package:flutter/material.dart';

import 'models.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 考试安排页。
class ExamPage extends StatefulWidget {
  const ExamPage({super.key, required this.api});

  final UrpApi api;

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  late Future<List<ExamRecord>> _future = widget.api.fetchExams();

  void _reload() {
    setState(() {
      _future = widget.api.fetchExams();
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
      body: FutureBuilder<List<ExamRecord>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<ExamRecord>> snapshot,
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

          final List<ExamRecord> exams = snapshot.data ?? const <ExamRecord>[];
          if (exams.isEmpty) {
            return const UrpEmptyView(
              icon: Icons.event_available_outlined,
              title: '还没有考试安排',
              detail: '教务处排考后会出现在这里。',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: exams.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) =>
                _ExamCard(record: exams[index]),
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
