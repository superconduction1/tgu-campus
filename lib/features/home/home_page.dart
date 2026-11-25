import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design.dart';
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
    return Scaffold(
      backgroundColor: TguColors.page,
      appBar: AppBar(
        backgroundColor: TguColors.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: TguColors.brand,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '天工校园',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: TguColors.ink,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, color: TguColors.sub),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          TodayCard(api: widget.api),
          const SectionTitle('校园服务'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.02,
            children: _modules.map((_ModuleEntry module) {
              final Color accent = TguColors.accentFor(module.title);
              return Container(
                decoration: BoxDecoration(
                  color: TguColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: TguColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openModule(module),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(module.icon, size: 19, color: accent),
                        ),
                        const Spacer(),
                        Text(
                          module.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TguColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          module.source,
                          style: const TextStyle(
                            fontSize: 11,
                            color: TguColors.sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SectionTitle('工具'),
          AppCard(
            padding: EdgeInsets.zero,
            child: AccentTile(
              accent: TguColors.sub,
              title: _dumping ? '正在导出诊断包…' : '导出诊断包',
              meta: '把教务真实页面存成文件，方便对着写解析器',
              onTap: _dumping ? null : _exportDump,
              trailing: const Icon(
                Icons.save_alt_outlined,
                size: 18,
                color: TguColors.sub,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
