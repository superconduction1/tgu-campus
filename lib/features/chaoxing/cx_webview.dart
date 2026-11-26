import 'package:webview_flutter/webview_flutter.dart';

import '../../core/http.dart';
import '../../core/session.dart';
import 'seat_rules.dart';

/// 把已保存的学习通会话 Cookie 注入 WebView。
///
/// 学习通的 H5 页面（作业详情、座位预约）都要登录态。用户已经在应用里
/// 登过一次学习通，这里就不该再让他输一遍密码：把 Cookie 按域铺到
/// WebView 的 CookieManager 里，页面打开就是登录状态。
///
/// 注入失败不抛异常——最坏情况是 WebView 自己弹登录页，用户手动登一次。
/// 返回写进去的 Cookie 条数，便于调用方决定要不要提示。
Future<int> injectCxCookies(String url, {WebViewCookieManager? manager}) async {
  final WebViewCookieManager cookies = manager ?? WebViewCookieManager();
  try {
    final CookieJar? jar = await _loadJar();
    if (jar == null) return 0;

    final List<String> domains = cookieDomainsFor(hostOfUrl(url));
    if (domains.isEmpty) return 0;

    int written = 0;
    for (final String domain in domains) {
      for (final MapEntry<String, String> entry in jar.entries.entries) {
        try {
          await cookies.setCookie(
            WebViewCookie(
              name: entry.key,
              value: entry.value,
              domain: domain,
            ),
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

/// 组装成 `k1=v1; k2=v2` 的 Cookie 头。
///
/// 光靠 CookieManager 铺域有时不够：学习通的服务端会看**首个文档请求**有没有
/// 带上会话 Cookie，缺了就回「请查看您的浏览器是否已经禁用cookie功能」。
/// 首文档单独带一个 Cookie 头最稳，子资源仍靠上面按域注入的那份。
Future<String> cxCookieHeader() async {
  try {
    final CookieJar? jar = await _loadJar();
    if (jar == null || jar.entries.isEmpty) return '';
    return jar.entries.entries
        .where((MapEntry<String, String> e) => e.key.isNotEmpty && e.value.isNotEmpty)
        .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .join('; ');
  } catch (_) {
    return '';
  }
}

Future<CookieJar?> _loadJar() async {
  final StoredCxCredentials? saved = await CxSessionStore().load();
  final String? payload = saved?.cookies;
  if (payload == null || payload.isEmpty) return null;
  final CookieJar jar = CookieJar()..restore(payload);
  if (jar.entries.isEmpty) return null;
  return jar;
}
