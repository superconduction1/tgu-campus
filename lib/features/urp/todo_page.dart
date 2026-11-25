import 'package:flutter/material.dart';

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
  const TodoPage({super.key, required this.api});

  final UrpApi api;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  late Future<List<TodoItem>> _future = _load();

  /// 学习通那边没取到作业（没登录 / 登录过期 / 网络不通）——只是少一份来源，
  /// 不该让整页报错，但要在底部说明一句，免得用户以为真没作业。
  bool _homeworkUnavailable = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<TodoItem>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<TodoItem>> snapshot,
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: <Widget>[
              for (final TodoItem todo in todos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TodoCard(
                    todo: todo,
                    onTap: todo.kind == TodoKind.homework && todo.path.isNotEmpty
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CxWebViewPage(
                                  title: todo.title,
                                  url: todo.path,
                                ),
                              ),
                            )
                        : null,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _homeworkUnavailable
                    ? '来源：URP 学分确认、学业预警（学习通作业没取到，可能登录过期）'
                    : '来源：URP 学分确认、学业预警、学习通未交作业',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.todo, this.onTap});

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

  static Color _colorFor(TodoKind kind, ColorScheme scheme) {
    switch (kind) {
      case TodoKind.creditConfirm:
        return scheme.primary;
      case TodoKind.warning:
        return scheme.error;
      case TodoKind.homework:
        return scheme.tertiary;
      case TodoKind.other:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = _colorFor(todo.kind, scheme);

    final BorderRadius radius = BorderRadius.circular(12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: radius,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_iconFor(todo.kind), size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      todo.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (todo.detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          todo.detail,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.outline),
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
