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
    final StoredCxCredentials? saved = await CxSessionStore().load();
    final String? payload = saved?.cookies;
    if (payload == null || payload.isEmpty) return 0;

    final CookieJar jar = CookieJar()..restore(payload);
    if (jar.entries.isEmpty) return 0;

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
