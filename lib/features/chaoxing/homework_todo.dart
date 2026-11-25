import '../urp/models.dart';
import 'models.dart';

/// 把「还没交的作业」翻成待办条目。
///
/// 只收未提交的：已交、待批阅、已批阅都不该出现在待办里烦人。
/// 顺序沿用传入的 [HomeworkList]（[HomeworkList.merge] 已把未交排前面）。
List<TodoItem> homeworkTodos(HomeworkList list) {
  final List<TodoItem> todos = <TodoItem>[];
  for (final HomeworkItem item in list.pending) {
    todos.add(
      TodoItem(
        title: item.title,
        detail: _detail(item),
        kind: TodoKind.homework,
        path: item.url,
      ),
    );
  }
  return todos;
}

String _detail(HomeworkItem item) {
  final List<String> parts = <String>[];
  if (item.courseName.isNotEmpty) parts.add(item.courseName);
  if (item.deadline.isNotEmpty) parts.add('截止 ${item.deadline}');
  return parts.join(' · ');
}
