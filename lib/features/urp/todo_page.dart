import 'package:flutter/material.dart';

import 'models.dart';
import 'urp_api.dart';
import 'urp_widgets.dart';

/// 待办页：把教务里几处「可能要你动手」的地方合成一张列表。
///
/// 现在接了两处：学分确认、学业预警。学习通作业接进来后
/// 会以 [TodoKind.homework] 出现在同一张卡片列表里。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.api});

  final UrpApi api;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  late Future<List<TodoItem>> _future = widget.api.fetchTodos();

  void _reload() {
    setState(() {
      _future = widget.api.fetchTodos();
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
            return const UrpEmptyView(
              icon: Icons.done_all_outlined,
              title: '眼下没有待办',
              detail: '学分确认和学业预警都是空的。学习通的作业接进来后，'
                  '需要交的作业也会出现在这里。',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: <Widget>[
              for (final TodoItem todo in todos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TodoCard(todo: todo),
                ),
              const SizedBox(height: 8),
              Text(
                '来源：URP 学分确认、学业预警',
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
  const _TodoCard({required this.todo});

  final TodoItem todo;

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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
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
        ],
      ),
    );
  }
}
