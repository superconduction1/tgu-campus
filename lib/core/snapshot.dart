/// 本地快照的编码格式与 key 规则。
///
/// 单独放一份纯 Dart，是因为它要能被不依赖 Flutter 的断言脚手架直接测。
library;

/// 一份带时间戳的快照。
///
/// 存下来的是「上次成功拿到的原始数据」，网络不通时用它兜底，
/// 界面会标明这是什么时候的数据。
class CachedSnapshot {
  const CachedSnapshot({required this.value, required this.savedAt});

  final String value;
  final DateTime savedAt;

  /// `11-25 19:40`，给界面上的「显示 xx 的数据」用。
  String get savedAtLabel => cachedLabel(savedAt);

  @override
  String toString() => 'CachedSnapshot(${value.length} 字节, $savedAtLabel)';
}

/// 把时间格式成 `11-25 19:40`，界面上统一用这一种写法。
String cachedLabel(DateTime at) {
  final DateTime t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 序列化成一行 JSON：`{"savedAt":<毫秒>,"value":"..."}`。
String encodeSnapshot(CachedSnapshot snapshot) {
  final String escaped = _escape(snapshot.value);
  return '{"savedAt":${snapshot.savedAt.millisecondsSinceEpoch},"value":"$escaped"}';
}

/// 解析失败一律返回 null——缓存坏了就当没有，不能让它把页面搞崩。
CachedSnapshot? decodeSnapshot(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final RegExpMatch? stamp = RegExp(r'"savedAt"\s*:\s*(-?\d+)').firstMatch(raw);
  if (stamp == null) return null;
  final int? millis = int.tryParse(stamp.group(1)!);
  if (millis == null) return null;

  // value 是最后一段，直接按位置取，避免为了一个字段引入 JSON 依赖差异。
  final int key = raw.indexOf('"value":"');
  if (key < 0) return null;
  final int start = key + '"value":"'.length;
  final int end = raw.lastIndexOf('"');
  if (end < start) return null;
  final String value = _unescape(raw.substring(start, end));
  return CachedSnapshot(
    value: value,
    savedAt: DateTime.fromMillisecondsSinceEpoch(millis),
  );
}

/// 文件名只允许这些字符，防止 key 里混进 `../` 之类的路径。
String sanitizeCacheKey(String key) {
  final String cleaned =
      key.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final String trimmed = cleaned.replaceAll(RegExp(r'^[._]+'), '');
  if (trimmed.isEmpty) return 'cache';
  return trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
}

String _escape(String input) {
  final StringBuffer out = StringBuffer();
  for (final int unit in input.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  return out.toString();
}

String _unescape(String input) {
  if (!input.contains(r'\')) return input;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final String ch = input[i];
    if (ch != r'\' || i == input.length - 1) {
      out.write(ch);
      continue;
    }
    final String next = input[++i];
    switch (next) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case '"':
        out.write('"');
      case r'\':
        out.write(r'\');
      case 'u':
        if (i + 4 < input.length) {
          final String hex = input.substring(i + 1, i + 5);
          final int? code = int.tryParse(hex, radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 4;
            break;
          }
        }
        out.write('u');
      default:
        out.write(next);
    }
  }
  return out.toString();
}
