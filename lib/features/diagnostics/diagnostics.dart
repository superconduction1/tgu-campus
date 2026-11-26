import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/config.dart';
import '../../core/http.dart';
import '../../core/session.dart';
import '../chaoxing/cx_api.dart';
import '../chaoxing/models.dart';
import '../urp/urp_api.dart';

/// 诊断转储：把登录后能拿到的原始 HTML 全部落盘。
///
/// 这是整个项目的「校准入口」。解析器只能对着真实页面写，
/// 与其猜 DOM 结构，不如先让 App 跑一次、把页面导出来。
class Diagnostics {
  Diagnostics(this.api);

  final UrpApi api;

  static const List<String> _probePaths = <String>[
    '/',
    '/index.jsp',
    '/frame/default/index.jsp',
    '/frame/index.jsp',
    '/logout',
  ];

  Future<String> exportUrpDump() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final DateTime now = DateTime.now();
    final String stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final File file = File('${dir.path}/urp_dump_$stamp.txt');

    final StringBuffer buffer = StringBuffer()
      ..writeln('# 天津工业大学 URP 诊断转储')
      ..writeln('# 时间：${now.toIso8601String()}')
      ..writeln('# 主机：${UrpConfig.host}')
      ..writeln('# Cookie：${api.client.jar.isEmpty ? "(空)" : api.client.jar.entries.keys.join(", ")}')
      ..writeln();

    for (final String path in _probePaths) {
      buffer.writeln('===== GET $path =====');
      try {
        final HttpResult result = await api.client.get(UrpConfig.page(path));
        buffer
          ..writeln('status   = ${result.statusCode}')
          ..writeln('length   = ${result.length}')
          ..writeln('location = ${result.location ?? "-"}')
          ..writeln('--- body ---');
        final String body = result.body;
        buffer.writeln(
          body.length > 100000 ? body.substring(0, 100000) : body,
        );
      } catch (error) {
        buffer.writeln('ERROR: $error');
      }
      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// 把第一门课的作业列表原始 HTML 落盘。
  ///
  /// 学习通的状态徽章 class 名改过好几版，靠猜关键词永远对不齐；
  /// 直接把服务端返回的那页存下来，对着 DOM 写解析器。
  Future<String> exportCxWorkListDump() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final DateTime now = DateTime.now();
    final String stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final File file = File('${dir.path}/cx_worklist_$stamp.html');

    final StoredCxCredentials? saved = await CxSessionStore().load();
    final String? cookies = saved?.cookies;
    if (cookies == null || cookies.isEmpty) {
      await file.writeAsString('<!-- 没有学习通登录态 -->');
      return file.path;
    }

    final SchoolHttpClient client = SchoolHttpClient();
    client.jar.restore(cookies);
    final ChaoxingApi cx = ChaoxingApi(client);
    final List<CxCourse> courses = await cx.fetchCourses();

    final StringBuffer out = StringBuffer()
      ..writeln('<!-- 学习通作业列表原始页面 -->')
      ..writeln('<!-- 时间：${now.toIso8601String()} -->')
      ..writeln('<!-- 课程数：${courses.length} -->');

    for (final CxCourse course in courses.take(3)) {
      out
        ..writeln('<!-- ===== ${course.name} '
            'courseId=${course.courseId} clazzId=${course.clazzId} ===== -->');
      final String? html = await cx.rawWorkListHtml(course);
      if (html == null) {
        out.writeln('<!-- 这门课没取到 -->');
        continue;
      }
      out.writeln(html);
    }

    await file.writeAsString(out.toString());
    return file.path;
  }
}
