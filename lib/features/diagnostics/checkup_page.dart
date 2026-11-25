import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_cache.dart';
import '../../core/disk_cache.dart';
import '../../core/http.dart';
import '../../core/session.dart';
import '../../core/snapshot.dart';
import '../chaoxing/cx_api.dart';
import '../chaoxing/models.dart';
import '../chaoxing/seat_rules.dart';
import '../chaoxing/seat_store.dart';
import '../urp/models.dart';
import '../urp/urp_api.dart';
import 'checkup.dart';

/// 一条条把各模块走一遍，把结果写成一段能直接发出去的文本。
///
/// 手机上出了问题，与其猜「哪个接口挂了」，不如让用户点一下自检、
/// 把这段文字发回来——每一项都带了耗时和失败原因。
class CheckupPage extends StatefulWidget {
  const CheckupPage({super.key, required this.api, this.cache});

  final UrpApi api;
  final DiskCache? cache;

  @override
  State<CheckupPage> createState() => _CheckupPageState();
}

class _CheckupPageState extends State<CheckupPage> {
  late final DiskCache _cache = widget.cache ?? appCache();

  bool _running = true;
  List<CheckupItem> _items = <CheckupItem>[];
  List<String> _facts = <String>[];
  String _report = '';

  @override
  void initState() {
    super.initState();
    unawaited(_runAll());
  }

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _items = <CheckupItem>[];
      _facts = <String>[];
    });

    final List<String> facts = <String>[
      '版本：$appVersion（${Platform.operatingSystem}）',
    ];
    final StoredCredentials? urp = await _quiet(SessionStore().load);
    final StoredCxCredentials? cx = await _quiet(CxSessionStore().load);
    final String? seat = await _quiet(SeatLinkStore().load);

    facts
      ..add('教务账号：${urp == null ? '未登录' : maskAccount(urp.username)}'
          '（Cookie ${urp?.cookies?.length ?? 0} 个）')
      ..add('学习通账号：${cx == null ? '未登录' : maskAccount(cx.phone)}'
          '（Cookie ${cx?.cookies?.length ?? 0} 个）')
      ..add('座位地址：${seat == null ? '未设置' : seat}');

    final List<CheckupItem> items = <CheckupItem>[];
    items.add(await _step('教务连通', () async {
      final HttpResult? landing = await widget.api.probeLanding();
      if (landing == null) {
        throw StateError('落地页一个都没匹配上');
      }
      return 'HTTP ${landing.statusCode}，长度 ${landing.length}';
    }));

    items.add(await _step('课表', () async {
      final Timetable timetable = await widget.api.fetchTimetable();
      return '${timetable.courses.length} 门课 / ${timetable.totalCredits} 学分';
    }));

    items.add(await _step('成绩', () async {
      final List<ScoreRecord> scores = await widget.api.fetchScores();
      return '${scores.length} 条';
    }));

    items.add(await _step('考试', () async {
      final List<ExamRecord> exams = await widget.api.fetchExams();
      return '${exams.length} 场';
    }));

    items.add(await _step('缓存', () async {
      final CachedSnapshot? snap = await _cache.load(CacheKeys.timetable);
      return snap == null ? '还没有课表快照' : '课表快照 ${snap.savedAtLabel}';
    }));

    // 学习通诸项都依赖登录态，没登录就直接标出来，别让它当成故障。
    if (cx == null || (cx.cookies?.isEmpty ?? true)) {
      items.add(const CheckupItem(
        name: '学习通',
        ok: false,
        detail: '没有登录态，作业页里登录一次再来自检',
      ));
    } else {
      final SchoolHttpClient client = SchoolHttpClient();
      client.jar.restore(cx.cookies!);
      final ChaoxingApi cxApi = ChaoxingApi(client);

      items.add(await _step('学习通课程', () async {
        final List<CxCourse> courses = await cxApi.fetchCourses();
        return '${courses.length} 门（${courses.map((CxCourse e) => e.name).take(3).join('、')}）';
      }));

      items.add(await _step('学习通作业', () async {
        final HomeworkList list = await cxApi.fetchHomework();
        final String extra =
            list.failedCount > 0 ? '，${list.failedCount} 门没取到' : '';
        return '${list.items.length} 条，待交 ${list.pendingCount}$extra';
      }));
    }

    items.add(await _step('座位地址', () async {
      if (seat == null || seat.isEmpty) {
        // 不是故障：座位预约要靠用户自己在学习通里粘一次地址。
        return '还没设置（首页 → 座位预约，按提示粘一次地址）';
      }
      final String? normalized = normalizeSeatUrl(seat);
      if (normalized == null) {
        throw StateError('地址不是学习通/学校的域名');
      }
      return normalized;
    }));

    if (!mounted) return;
    setState(() {
      _running = false;
      _facts = facts;
      _items = items;
      _report = formatCheckup(
        title: '天工校园 自检报告',
        facts: facts,
        items: items,
      );
    });
  }

  /// 跑一步，超时或异常都变成一条 ❌，不中断后面的项。
  Future<CheckupItem> _step(String name, Future<String> Function() body) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final String detail =
          await body().timeout(const Duration(seconds: 25));
      return CheckupItem(
        name: name,
        ok: true,
        detail: detail,
        millis: watch.elapsedMilliseconds,
      );
    } catch (error) {
      return CheckupItem(
        name: name,
        ok: false,
        detail: _explain(error),
        millis: watch.elapsedMilliseconds,
      );
    }
  }

  String _explain(Object error) {
    if (error is UrpSessionExpiredException) {
      return '教务登录过期，回首页重新登录';
    }
    if (error is TimeoutException) {
      return '超时 25 秒没响应';
    }
    final String text = error.toString().replaceAll('\n', ' ');
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  /// 读本地凭据本身也可能抛（Keystore 解不开），这里不该把自检搞挂。
  Future<T?> _quiet<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自检报告已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自检'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新自检',
            onPressed: _running ? null : () => unawaited(_runAll()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _running
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在挨个试…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                ..._facts.map(
                  (String fact) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(fact, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
                const Divider(height: 24),
                ..._items.map(
                  (CheckupItem item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.ok ? Icons.check_circle : Icons.error_outline,
                      color: item.ok ? scheme.primary : scheme.error,
                    ),
                    title: Text(item.name),
                    subtitle: Text(item.detail),
                    trailing: item.millis == null
                        ? null
                        : Text('${item.millis}ms',
                            style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制报告'),
                ),
                const SizedBox(height: 8),
                Text(
                  '报告里只有账号后几位和接口结果，不含密码。',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
    );
  }
}
