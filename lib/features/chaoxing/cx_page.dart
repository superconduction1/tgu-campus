import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/http.dart';
import '../../core/session.dart';
import 'cx_webview.dart';

/// 用内置 WebView 打开一个学习通页面，并先把登录 Cookie 铺进去。
///
/// 作业详情、待办里的作业条目都走这里：进来就是登录态，不用再输一遍密码。
/// 只做「看」——提交作业、预约座位仍是用户自己在页面里点。
class CxWebViewPage extends StatefulWidget {
  const CxWebViewPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<CxWebViewPage> createState() => _CxWebViewPageState();
}

class _CxWebViewPageState extends State<CxWebViewPage> {
  WebViewController? _controller;
  int _progress = 0;
  int _injected = 0;
  String? _error;
  bool _fallbackUsed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    // 先把学习通会话 Cookie 铺进 WebView。
    final int injected = await injectCxCookies(widget.url);
    if (!mounted) return;

    // 首文档再单独带一份 Cookie 头：学习通看首个请求有没有会话，
    // 只看 CookieManager 有时会回「浏览器已禁用cookie功能」。
    final String cookieHeader = await cxCookieHeader(widget.url);
    if (!mounted) return;

    final WebViewController controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
        onWebResourceError: (WebResourceError error) {
          if (!mounted) return;
          // 只有主文档失败才算页面失败，图片/脚本失败不该盖掉内容。
          if (!error.isForMainFrame.orTrue) return;
          setState(() => _error = error.description);
        },
        onPageFinished: (String url) => _checkCookieWall(controller, url),
      ),
    );
    await controller.loadRequest(
      Uri.parse(widget.url),
      headers: cookieHeader.isEmpty
          ? const <String, String>{}
          : <String, String>{'Cookie': cookieHeader},
    );

    setState(() {
      _controller = controller;
      _injected = injected;
    });
  }

  /// 学习通会把「没带会话」伪装成一个正常的 200 页面：
  /// 正文只有一句「请查看您的浏览器是否已经禁用cookie功能」。
  ///
  /// 碰到这个页面就换一条路：用 Dart 这边的客户端（它的会话是好的，
  /// 作业列表就是它拉的）把同一个地址取回来，把 HTML 直接塞给 WebView。
  /// 页面里的相对链接靠 [WebViewController.loadHtmlString] 的 baseUrl 兜住。
  Future<void> _checkCookieWall(WebViewController controller, String url) async {
    if (!mounted || _fallbackUsed) return;
    try {
      final Object? text =
          await controller.runJavaScriptReturningResult('document.body.innerText');
      final String body = text.toString();
      if (!body.contains('禁用cookie') && !body.contains('禁用 cookie')) return;

      _fallbackUsed = true;
      final Uri? uri = Uri.tryParse(url);
      if (uri == null) return;

      final StoredCxCredentials? saved = await CxSessionStore().load();
      final String? cookies = saved?.cookies;
      final SchoolHttpClient client = SchoolHttpClient();
      if (cookies != null && cookies.isNotEmpty) client.jar.restore(cookies);

      final String? origin = uri.hasScheme
          ? '${uri.scheme}://${uri.host}'
          : null;
      final HttpResult result = await client.get(
        uri,
        headers: origin == null
            ? null
            : <String, String>{'Referer': '$origin/'},
      );
      if (!mounted) return;
      await controller.loadHtmlString(result.html, baseUrl: url);
    } catch (_) {
      // 兜底失败就维持原样，用户还能点右上角用浏览器打开。
    }
  }

  Future<void> _openInBrowser() async {
    final Uri? uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没能打开浏览器')),
      );
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _progress = 0;
    });
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (controller != null)
            IconButton(
              tooltip: '刷新',
              onPressed: () => controller.reload(),
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: '在浏览器打开',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: _buildBody(controller),
    );
  }

  Widget _buildBody(WebViewController? controller) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text('页面没能打开：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _retry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: <Widget>[
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        if (_injected == 0) const _LoggedOutHint(),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    );
  }
}

/// 没注入到 Cookie 时的提示：页面里八成会要求登录学习通。
class _LoggedOutHint extends StatelessWidget {
  const _LoggedOutHint();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '学习通登录态没带过来，页面里可能需要你再登一次',
        style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
      ),
    );
  }
}

extension _BoolOrTrue on bool? {
  bool get orTrue => this ?? true;
}
