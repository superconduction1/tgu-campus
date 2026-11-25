// 真正的类型层检查：用 analyzer 的 AnalysisContextCollection 做完整解析。
//
// 和 syntax.dart 的区别：syntax.dart 只解析语法（不解析 import），
// 这个脚本会把 package:flutter 一起解析进来，所以能抓出
// 「方法不存在」「参数类型不匹配」「构造函数缺参数」这类错误。
//
// 之所以不用 `dart analyze`：它会 spawn 一个 analysis_server 子进程，
// 而沙箱里不允许创建管道，子进程起不来。这里全程在本进程里完成。
//
// 前提：项目根目录要有 .dart_tool/package_config.json（dart pub get 生成，
// 且 FLUTTER_ROOT 必须指向 Flutter SDK，否则 sdk: flutter 解析不了）。
//
// 用法（在 tools/verify 目录）：
//   dart run bin/resolve.dart

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';

Future<void> main(List<String> args) async {
  // 默认查 lib 和 test：CI 里跑的是 `flutter analyze`，它会连 test/ 一起分析，
  // 所以本地也得把 test/ 纳入，否则 CI 才第一次见到那些问题。
  final List<String> targets = args.isNotEmpty
      ? args
      : <String>['../../lib', '../../test'];

  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    stderr.writeln('没有设置 FLUTTER_ROOT，无法解析 package:flutter');
    exit(2);
  }
  final Directory rawSdk = Directory('$flutterRoot/bin/cache/dart-sdk');
  if (!rawSdk.existsSync()) {
    stderr.writeln('FLUTTER_ROOT 下没有 dart-sdk：${rawSdk.path}');
    exit(2);
  }
  // 同样要归一化：'/bin/cache' 里的斜杠会让 analyzer 认为路径没归一
  final String sdkPath = rawSdk.resolveSymbolicLinksSync();

  final Directory projectRoot = Directory('../..').absolute;
  // 用归一化后的路径做前缀裁剪，否则拿到的短路径还是绝对路径
  final String rootPrefix =
      '${projectRoot.resolveSymbolicLinksSync().replaceAll('\\', '/')}/';
  final List<String> includedPaths = <String>[];
  final List<File> files = <File>[];

  for (final String target in targets) {
    final Directory dir = Directory(target);
    if (!dir.existsSync()) {
      stderr.writeln('跳过不存在的目录：$target');
      continue;
    }
    // analyzer 只接受绝对且已归一化的路径，'../../lib' 带 .. 会被拒
    final String resolved = dir.resolveSymbolicLinksSync();
    includedPaths.add(resolved);
    files.addAll(Directory(resolved)
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart')));
  }

  if (includedPaths.isEmpty) {
    stderr.writeln('没有可检查的目录（请在 tools/verify 下运行）');
    exit(2);
  }

  final AnalysisContextCollection collection = AnalysisContextCollection(
    includedPaths: includedPaths,
    sdkPath: sdkPath,
  );

  files.sort((File a, File b) => a.path.compareTo(b.path));

  int checked = 0;
  int errors = 0;
  int warnings = 0;

  for (final File file in files) {
    checked++;
    final String path = file.resolveSymbolicLinksSync();
    final String short = path
        .replaceAll('\\', '/')
        .replaceFirst(rootPrefix, '');
    final AnalysisContext context = collection.contextFor(path);
    final SomeResolvedUnitResult result =
        await context.currentSession.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      stdout.writeln('  ??    $short（没有解析结果：$result）');
      continue;
    }
    final List<Diagnostic> serious = result.diagnostics
        .where((Diagnostic d) =>
            d.severity == Severity.error || d.severity == Severity.warning)
        .toList();
    if (serious.isEmpty) {
      stdout.writeln('  OK    $short');
      continue;
    }
    stdout.writeln('  FAIL  $short');
    for (final Diagnostic d in serious) {
      final CharacterLocation loc = result.lineInfo.getLocation(d.offset);
      final String tag = d.severity == Severity.error ? 'error' : 'warn ';
      stdout.writeln('        $tag ${loc.lineNumber}:${loc.columnNumber}  ${d.message}');
      if (d.severity == Severity.error) {
        errors++;
      } else {
        warnings++;
      }
    }
  }

  await collection.dispose();

  stdout.writeln('\n类型检查：$checked 个文件，$errors 个 error，$warnings 个 warning\n');
  if (errors > 0) exit(1);
}
