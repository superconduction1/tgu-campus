import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/http.dart';
import '../../core/session.dart';
import '../chaoxing/cx_api.dart';
import '../chaoxing/cx_page.dart';
import '../chaoxing/homework_todo.dart';
import '../chaoxing/models.dart';
import 'models.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 待办页：把几处「可能要你动手」的地方合成一张列表。
///
/// 教务那两处是学分确认和学业预警；学习通那边还没交的作业也放进来，
/// 这样不用为了看一眼有没有作业在「待办」和「作业」之间来回切。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.api, this.embedded = false});

  final UrpApi api;

  /// 嵌到底部 tab 里时不要自己的 AppBar。
  final bool embedded;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  late Future<List<TodoItem>> _future = _load();

  /// 学习通那边没取到作业（没登录 / 登录过期 / 网络不通）——只是少一份来源，
  /// 不该让整页报错，但要在底部说明一句，免得用户以为真没作业。
  bool _homeworkUnavailable = false;

  /// 自己持有滚动控制器：内嵌到 HomeShell 的 IndexedStack 里时，
  /// 外层的 PrimaryScrollController 已被课表页占用，共用会让本页视口不绘制。

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<TodoItem>> _load() async {
    final List<TodoItem> urp = await widget.api.fetchTodos();
    final List<TodoItem> homework = await _loadHomeworkTodos();
    // 未交作业排最前面：这是唯一有截止时间的东西。
    return <TodoItem>[...homework, ...urp];
  }

  Future<List<TodoItem>> _loadHomeworkTodos() async {
    try {
      final StoredCxCredentials? saved = await CxSessionStore().load();
      final String? cookies = saved?.cookies;
      if (cookies == null || cookies.isEmpty) return const <TodoItem>[];
      final SchoolHttpClient client = SchoolHttpClient();
      client.jar.restore(cookies);
      final HomeworkList list = await ChaoxingApi(client).fetchHomework();
      return homeworkTodos(list);
    } catch (_) {
      _homeworkUnavailable = true;
      return const <TodoItem>[];
    }
  }

  void _reload() {
    setState(() {
      _homeworkUnavailable = false;
      _future = _load();
    });
  }

  void _open(TodoItem todo) {
    if (todo.kind != TodoKind.homework || todo.path.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CxWebViewPage(title: todo.title, url: todo.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TguColors.page,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('待办'),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              actions: <Widget>[
                IconButton(
                  tooltip: '刷新',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  color: TguColors.sub,
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          FutureBuilder<List<TodoItem>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<TodoItem>> snapshot,
        ) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return UrpErrorView(
              error: snapshot.error!,
              onRetry: _reload,
              onRelogin: () => urpRelogin(context, widget.api),
            );
          }

          final List<TodoItem> todos = snapshot.data ?? const <TodoItem>[];
          if (todos.isEmpty) {
            return UrpEmptyView(
              icon: Icons.done_all_outlined,
              title: '眼下没有待办',
              detail: _homeworkUnavailable
                  ? '学分确认和学业预警都是空的；学习通的作业没取到，'
                      '可能登录过期了，去「作业」页重新登一次。'
                  : '学分确认、学业预警、学习通作业都是空的。',
            );
          }

          final int pending =
              todos.where((TodoItem t) => t.kind == TodoKind.homework).length;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
              if (pending > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _PendingBanner(count: pending),
                ),
              SectionTitle(
                '全部待办',
                trailing: Text(
                  '${todos.length} 项',
                  style: const TextStyle(fontSize: 12, color: TguColors.sub),
                ),
              ),
              const SizedBox(height: 8),
              for (final TodoItem todo in todos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TodoTile(
                    todo: todo,
                    onTap: todo.path.isEmpty ? null : () => _open(todo),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _homeworkUnavailable
                    ? '来源：URP 学分确认、学业预警（学习通作业没取到，可能登录过期）'
                    : '来源：URP 学分确认、学业预警、学习通未交作业',
                style: const TextStyle(fontSize: 11.5, color: TguColors.sub),
                textAlign: TextAlign.center,
              ),
            ],
            ),
          );
        },
          ),
        ],
      ),
    );
  }
}

/// 顶部「还有 N 份作业没交」的提醒条。
class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: TguColors.brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: TguColors.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '学习通还有 $count 份作业没交',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TguColors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.todo, this.onTap});

  final TodoItem todo;
  final VoidCallback? onTap;

  static IconData _iconFor(TodoKind kind) {
    switch (kind) {
      case TodoKind.creditConfirm:
        return Icons.verified_user_outlined;
      case TodoKind.warning:
        return Icons.warning_amber_outlined;
      case TodoKind.homework:
        return Icons.assignment_outlined;
      case TodoKind.other:
        return Icons.task_alt_outlined;
    }
  }

  static String _labelFor(TodoKind kind) {
    switch (kind) {
      case TodoKind.creditConfirm:
        return '学分确认';
      case TodoKind.warning:
        return '学业预警';
      case TodoKind.homework:
        return '学习通';
      case TodoKind.other:
        return '其他';
    }
  }

  static Color _colorFor(TodoKind kind) {
    switch (kind) {
      case TodoKind.creditConfirm:
        return TguColors.brand;
      case TodoKind.warning:
        return const Color(0xFFD93A3A);
      case TodoKind.homework:
        return TguColors.accents[3];
      case TodoKind.other:
        return TguColors.sub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _colorFor(todo.kind);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Icon(_iconFor(todo.kind), size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    todo.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: TguColors.ink,
                      height: 1.25,
                    ),
                  ),
                  if (todo.detail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      todo.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TguColors.sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SoftBadge(_labelFor(todo.kind), color: color),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 18, color: TguColors.sub),
          ],
        ),
      ),
    );
  }
}
