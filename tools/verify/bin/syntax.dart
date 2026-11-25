// 纯语法检查：把 lib 下每个 .dart 文件都解析一遍。
//
// 用 analyzer 的 parseString，只做语法层面的事，不做符号解析——
// 所以即使机器上没有 Flutter SDK、import 解析不了，也能查出语法错误
// （括号不配对、字符串没闭合、忘了分号之类）。

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';

void main() {
  final Directory root = Directory('../../lib');
  if (!root.existsSync()) {
    stderr.writeln('找不到 lib 目录');
    exit(2);
  }

  final List<File> files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  int checked = 0;
  int broken = 0;

  for (final File file in files) {
    checked++;
    final ParseStringResult result = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    // parseString 只做语法解析，它报的都是语法层面的问题
    final List<AnalysisError> errors = result.errors.toList();
    final String short = file.path.replaceAll('\\', '/').split('/lib/').last;
    if (errors.isEmpty) {
      stdout.writeln('  OK    $short');
    } else {
      broken++;
      stdout.writeln('  FAIL  $short');
      for (final AnalysisError e in errors) {
        final int line = result.lineInfo.getLocation(e.offset).lineNumber;
        stdout.writeln('        第 $line 行: ${e.message}');
      }
    }
  }

  stdout.writeln('\n语法检查：$checked 个文件，$broken 个有问题\n');
  if (broken > 0) exit(1);
}
