import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/session.dart';
import '../chaoxing/homework_page.dart';
import '../chaoxing/seat_page.dart';
import '../diagnostics/checkup_page.dart';
import '../settings/settings_page.dart';
import '../urp/exam_page.dart';
import '../urp/score_page.dart';
import '../urp/timetable_page.dart';
import '../urp/todo_page.dart';
import '../urp/urp_api.dart';

/// 主框架：底部四个 tab —— 课程 / 日程 / 学习 / 我的。
///
/// 参考了主流校园 App 的信息结构：课表是每天都要看的，放第一个；
/// 待办和通知合到「日程」；成绩、考试、作业、座位这些低频入口收进「学习」；
/// 账号与设置在「我的」。每个 tab 自己的 AppBar 都关掉了，统一用这里的页头。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.api,
    required this.store,
    this.initialTab = 0,
  });

  final UrpApi api;
  final SessionStore store;
  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialTab;

  static const List<String> _titles = <String>['课程', '日程', '学习', '我的'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TguColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(title: _titles[_index]),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: <Widget>[
                  TimetablePage(api: widget.api, embedded: true),
                  TodoPage(api: widget.api, embedded: true),
                  _LearnTab(api: widget.api),
                  SettingsPage(
                    api: widget.api,
                    store: widget.store,
                    embedded: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: TguColors.brand.withValues(alpha: 0.10),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week, color: TguColors.brand),
            label: '课程',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note, color: TguColors.brand),
            label: '日程',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school, color: TguColors.brand),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: TguColors.brand),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 四个 tab 共用的页头：校徽 + 校名 + 当前 tab 名。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: TguColors.brand,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.school, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '天津工业大学',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: TguColors.ink,
                  height: 1.1,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: TguColors.sub,
                  height: 1.3,
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// 「学习」tab：把成绩、考试、作业、座位这些入口收在一页里。
class _LearnTab extends StatelessWidget {
  const _LearnTab({required this.api});

  final UrpApi api;

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final List<_Entry> entries = <_Entry>[
      _Entry(
        '作业',
        '学习通 · 待交与已批阅',
        Icons.assignment_outlined,
        TguColors.accents[1],
        () => _push(context, const HomeworkPage()),
      ),
      _Entry(
        '座位预约',
        '学习通 · 22:00 开放',
        Icons.chair_outlined,
        TguColors.accents[3],
        () => _push(context, const SeatPage()),
      ),
      _Entry(
        '成绩',
        'URP · 学分与绩点',
        Icons.insert_chart_outlined,
        TguColors.accents[0],
        () => _push(context, ScorePage(api: api)),
      ),
      _Entry(
        '考试',
        'URP · 考场与时间',
        Icons.event_available_outlined,
        TguColors.accents[2],
        () => _push(context, ExamPage(api: api)),
      ),
      _Entry(
        '运行自检',
        '逐个模块试一遍',
        Icons.fact_check_outlined,
        TguColors.accents[4],
        () => _push(context, CheckupPage(api: api)),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: <Widget>[
        const SectionTitle('校园服务'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < entries.length; i++)
                _LearnRow(
                  entry: entries[i],
                  showDivider: i != entries.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _Entry {
  const _Entry(this.title, this.subtitle, this.icon, this.color, this.onTap);

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _LearnRow extends StatelessWidget {
  const _LearnRow({required this.entry, required this.showDivider});

  final _Entry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: TguColors.line))
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: entry.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(entry.icon, size: 18, color: entry.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: TguColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: TguColors.sub,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: TguColors.sub, size: 20),
          ],
        ),
      ),
    );
  }
}
