import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';

/// 超星（学习通）的编码声明不可信。
///
/// 实测：`content-type` 写 `charset=gbk` 的页面，正文其实是 UTF-8；
/// 反过来也有真 GBK 的页面。所以只能嗅探——
/// 先按 UTF-8 严格解码，抛 `FormatException` 再退回 GBK。
/// 反之若按声明直接解 GBK，好页面会被解成「鏃犳潈闄愮殑鎿嶄綔」这种乱码，
/// 关键词与解析规则会整页失效。
String decodeHtmlBytes(List<int> bytes, {String? declaredCharset}) {
  if (bytes.isEmpty) return '';

  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 不是合法 UTF-8，继续往下试 GBK。
  }

  final String charset = (declaredCharset ?? '').toLowerCase();
  if (charset.isEmpty || _gbkAliases.contains(charset)) {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      // GBK 表里没有的字节，退到宽松 UTF-8。
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 从 `content-type` 里取 charset，取不到返回 null。
String? charsetOf(String? contentType) {
  if (contentType == null || contentType.isEmpty) return null;
  final RegExpMatch? m = RegExp('charset\\s*=\\s*["\']?([\\w-]+)',
          caseSensitive: false)
      .firstMatch(contentType);
  return m?.group(1)?.toLowerCase();
}

const Set<String> _gbkAliases = <String>{
  'gbk',
  'gb2312',
  'gb18030',
  'cp936',
  'x-gbk',
};
