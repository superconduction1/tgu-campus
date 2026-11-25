import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cx_webview.dart';
import 'models.dart';

/// 作业详情：用内置 WebView 打开学习通的作业页。
///
/// 只做「看」——题目、要求、已交/未交状态、批阅结果都在这个页面里。
/// 真正提交作业仍然是用户在学习通里点，本应用不代做也不代交。
class HomeworkDetailPage extends StatefulWidget {
  const HomeworkDetailPage({super.key, required this.item});

  final HomeworkItem item;

  @override
  State<HomeworkDetailPage> createState() => _HomeworkDetailPageState();
}

class _HomeworkDetailPageState extends State<HomeworkDetailPage> {
  WebViewController? _controller;
  int _progress = 0;
  int _injected = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final String url = widget.item.url;
    if (url.isEmpty) return;

    // 先把学习通会话 Cookie 铺进 WebView，页面打开就是登录态，
    // 免得用户在这个页面再登一次。
    final int injected = await injectCxCookies(url);
    if (!mounted) return;

    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
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
        ),
      )
      ..loadRequest(Uri.parse(url));

    setState(() {
      _controller = controller;
      _injected = injected;
    });
  }

  Future<void> _openInBrowser() async {
    final Uri? uri = Uri.tryParse(widget.item.url);
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

  @override
  Widget build(BuildContext context) {
    final WebViewController? controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item.title.isEmpty ? '作业' : widget.item.title,
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
          if (widget.item.url.isNotEmpty)
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
    if (widget.item.url.isEmpty) {
      return const Center(child: Text('这条作业没有可打开的链接'));
    }
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
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _progress = 0;
                  });
                  _open();
                },
                child: const Text('重试'),
              ),
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
        if (_injected == 0) _LoggedOutHint(),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    );
  }
}

/// 没注入到 Cookie 时的提示：页面里八成会要求登录学习通。
class _LoggedOutHint extends StatelessWidget {
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
