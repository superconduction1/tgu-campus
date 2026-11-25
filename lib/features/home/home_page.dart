import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session.dart';
import '../chaoxing/homework_page.dart';
import '../chaoxing/seat_page.dart';
import '../diagnostics/diagnostics.dart';
import '../settings/settings_page.dart';
import '../urp/exam_page.dart';
import '../urp/score_page.dart';
import '../urp/timetable_page.dart';
import '../urp/today_card.dart';
import '../urp/todo_page.dart';
import '../urp/urp_api.dart';

class _ModuleEntry {
  const _ModuleEntry(this.title, this.source, this.icon);

  final String title;
  final String source;
  final IconData icon;
}

const List<_ModuleEntry> _modules = <_ModuleEntry>[
  _ModuleEntry('课表', 'URP', Icons.calendar_month_outlined),
  _ModuleEntry('成绩', 'URP', Icons.grading_outlined),
  _ModuleEntry('考试', 'URP', Icons.event_note_outlined),
  _ModuleEntry('待办', 'URP', Icons.checklist_outlined),
  _ModuleEntry('作业', '学习通', Icons.assignment_outlined),
  _ModuleEntry('座位预约', '学习通', Icons.event_seat_outlined),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.store});

  final UrpApi api;
  final SessionStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _dumping = false;

  Future<void> _exportDump() async {
    setState(() => _dumping = true);
    try {
      final String path = await Diagnostics(widget.api).exportUrpDump();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('诊断包已导出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('把这个文件发给我，我就能对着真实页面写解析器：'),
              const SizedBox(height: 12),
              SelectableText(
                path,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: path));
                Navigator.of(context).pop();
              },
              child: const Text('复制路径'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on FileSystemException catch (error) {
      _toast('写文件失败：${error.message}');
    } catch (error) {
      _toast('导出失败：$error');
    } finally {
      if (mounted) setState(() => _dumping = false);
    }
  }

  void _openModule(_ModuleEntry module) {
    switch (module.title) {
      case '课表':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TimetablePage(api: widget.api),
          ),
        );
        return;
      case '成绩':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ScorePage(api: widget.api),
          ),
        );
        return;
      case '考试':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExamPage(api: widget.api),
          ),
        );
        return;
      case '待办':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TodoPage(api: widget.api),
          ),
        );
        return;
      case '作业':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const HomeworkPage(),
          ),
        );
        return;
      case '座位预约':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SeatPage(),
          ),
        );
        return;
    }
    _toast('${module.title}：待接入（需先校准接口）');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(api: widget.api, store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('天工校园'),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TodayCard(api: widget.api),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _dumping ? null : _exportDump,
              icon: _dumping
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_outlined, size: 16),
              label: Text(
                _dumping ? '导出中…' : '导出诊断包',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '功能模块',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: _modules.map((_ModuleEntry module) {
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openModule(module),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(module.icon, size: 32, color: scheme.primary),
                      const SizedBox(height: 8),
                      Text(module.title),
                      const SizedBox(height: 2),
                      Text(
                        module.source,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
