import 'package:webview_flutter/webview_flutter.dart';

import '../../core/http.dart';
import '../../core/session.dart';
import 'seat_rules.dart';

/// 把已保存的学习通会话 Cookie 注入 WebView。
///
/// 学习通每个子域（passport2 / i / mooc1 / mooc2-ans）各有自己的
/// `JSESSIONID`，所以注入必须**按域分开**：把 `mooc1.chaoxing.com` 的会话
/// 写到 `mooc1.chaoxing.com`，别拿 `i.chaoxing.com` 的去顶替。
///
/// 注入失败不抛异常——最坏情况是 WebView 自己弹登录页，用户手动登一次。
/// 返回写进去的 Cookie 条数，便于调用方决定要不要提示。
Future<int> injectCxCookies(String url, {WebViewCookieManager? manager}) async {
  final WebViewCookieManager cookies = manager ?? WebViewCookieManager();
  try {
    final StoredCxCredentials? saved = await CxSessionStore().load();
    if (saved == null) return 0;

    final Map<String, Map<String, String>> groups =
        _pickCookies(saved, hostOfUrl(url));
    if (groups.isEmpty) return 0;

    int written = 0;
    for (final MapEntry<String, Map<String, String>> group in groups.entries) {
      for (final MapEntry<String, String> c in group.value.entries) {
        try {
          await cookies.setCookie(
            WebViewCookie(name: c.key, value: c.value, domain: group.key),
          );
          written++;
        } catch (_) {
          // 单个 Cookie 写不进去不影响主流程。
        }
      }
    }
    return written;
  } catch (_) {
    return 0;
  }
}

/// 组装成 `k1=v1; k2=v2` 的 Cookie 头，只带**这个域该带的**那些。
///
/// 光靠 CookieManager 铺域有时不够：学习通的服务端会看**首个文档请求**有没有
/// 带上会话 Cookie，缺了就回「请查看您的浏览器是否已经禁用cookie功能」。
Future<String> cxCookieHeader(String url) async {
  try {
    final StoredCxCredentials? saved = await CxSessionStore().load();
    if (saved == null) return '';
    final Map<String, Map<String, String>> groups =
        _pickCookies(saved, hostOfUrl(url));
    if (groups.isEmpty) return '';

    // 越具体的域越先放；同名 Cookie 只保留第一个（更具体的那个）。
    final Set<String> seen = <String>{};
    final List<String> parts = <String>[];
    for (final Map<String, String> bucket in groups.values) {
      for (final MapEntry<String, String> c in bucket.entries) {
        if (c.key.isEmpty || c.value.isEmpty) continue;
        if (!seen.add(c.key)) continue;
        parts.add('${c.key}=${c.value}');
      }
    }
    return parts.join('; ');
  } catch (_) {
    return '';
  }
}

/// 挑出目标域该用的 Cookie 组，顺序是「精确域 → 父域」。
///
/// 没有按域存档（老版本存的、或账号密码登录那条路）时，退回拍平的那份，
/// 只往目标域上铺——至少不会把别的域的会话串过来。
Map<String, Map<String, String>> _pickCookies(
  StoredCxCredentials saved,
  String host,
) {
  final Map<String, Map<String, String>> perHost = saved.cookieHosts;
  if (perHost.isNotEmpty) {
    final List<String> keys = perHost.keys
        .where((String h) => h.isNotEmpty && (host == h || host.endsWith('.$h')))
        .toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    if (keys.isNotEmpty) {
      return <String, Map<String, String>>{
        for (final String h in keys) h: perHost[h]!,
      };
    }
  }

  final String? flatPayload = saved.cookies;
  if (flatPayload == null || flatPayload.isEmpty) {
    return const <String, Map<String, String>>{};
  }
  final CookieJar jar = CookieJar()..restore(flatPayload);
  if (jar.entries.isEmpty) return const <String, Map<String, String>>{};
  return <String, Map<String, String>>{host: jar.entries};
}
