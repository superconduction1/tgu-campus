/// 自检报告的纯 Dart 部分：条目结构与文本排版。
///
/// 页面负责真正发请求，这里只负责「怎么把结果写成一段能直接发出去的话」，
/// 所以它能被断言脚手架直接测。
library;

/// 版本号，装机第一天排查问题时要能说清跑的是哪一版。
const String appVersion = '0.1.0';

class CheckupItem {
  const CheckupItem({
    required this.name,
    required this.ok,
    required this.detail,
    this.millis,
  });

  final String name;
  final bool ok;
  final String detail;

  /// 这一步花了多久，用来区分「慢」和「挂」。
  final int? millis;

  String get mark => ok ? '✅' : '❌';
}

/// 拼成一段纯文本：手机上长按复制，直接发出去就能看。
String formatCheckup({
  required String title,
  required List<String> facts,
  required List<CheckupItem> items,
  DateTime? now,
}) {
  final DateTime stamp = (now ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final StringBuffer out = StringBuffer()
    ..writeln(title)
    ..writeln('时间：${stamp.year}-${two(stamp.month)}-${two(stamp.day)} '
        '${two(stamp.hour)}:${two(stamp.minute)}:${two(stamp.second)}');
  for (final String fact in facts) {
    out.writeln(fact);
  }
  out
    ..writeln()
    ..writeln('— 自检项 —');
  for (final CheckupItem item in items) {
    final String cost = item.millis == null ? '' : '（${item.millis}ms）';
    out.writeln('${item.mark} ${item.name}：${item.detail}$cost');
  }
  final int okCount = items.where((CheckupItem e) => e.ok).length;
  out
    ..writeln()
    ..writeln('小结：$okCount/${items.length} 项正常');
  return out.toString();
}

/// 学号 / 手机号打码：自检报告可能会被转发，别把完整号码带出去。
String maskAccount(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return '(空)';
  if (text.length <= 4) return '${text[0]}***';
  return '${text.substring(0, 3)}***${text.substring(text.length - 2)}';
}
