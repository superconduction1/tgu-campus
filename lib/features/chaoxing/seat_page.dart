import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'cx_webview.dart';
import 'seat_rules.dart';
import 'seat_store.dart';

/// 座位预约。
///
/// 学校这个应用只挂在学习通 App 里（网页版、桌面版都没有入口），
/// 地址是 `<某>.mh.chaoxing.com/engine2/general/more?t=<令牌>`，
/// 令牌每校唯一、猜不出来，所以这里让用户粘一次，存起来复用。
/// 页面本身是 H5，预约 / 退约 / 记录都在里面完成；**不做自动签到**。
class SeatPage extends StatefulWidget {
  const SeatPage({super.key, this.store});

  final SeatLinkStore? store;

  @override
  State<SeatPage> createState() => _SeatPageState();
}

class _SeatPageState extends State<SeatPage> {
  late final SeatLinkStore _store = widget.store ?? SeatLinkStore();

  bool _booting = true;
  String? _url;
  String? _loadError;
  int _progress = 0;
  Timer? _ticker;
  String _countdown = seatCountdownLabel(DateTime.now());

  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    _restore();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _countdown = seatCountdownLabel(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final String? saved = await _store.load();
    if (!mounted) return;
    setState(() {
      _url = saved;
      _booting = false;
    });
    if (saved != null) unawaited(_openWebView(saved));
  }

  /// 把「作业」页登录学习通时存下的 Cookie 注进 WebView。
  ///
  /// 座位页判断登录态靠的就是这些 Cookie；用户登过一次作业，
  /// 这里就不该再问一遍密码。注入失败也没关系，WebView 会自己弹登录页。
  Future<void> _injectCxCookies(String url) => injectCxCookies(url, manager: _cookieManager);

  Future<void> _openWebView(String url) async {
    await _injectCxCookies(url);
    if (!mounted) return;
    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int p) {
            if (!mounted) return;
            setState(() => _progress = p);
          },
          onPageFinished: (String _) {
            if (!mounted) return;
            setState(() {
              _progress = 100;
              _loadError = null;
            });
          },
          onWebResourceError: (WebResourceError e) {
            if (!mounted || !e.isForMainFrame.orTrue) return;
            setState(() => _loadError = e.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    setState(() {
      _web = controller;
      _loadError = null;
    });
  }

  Future<void> _saveUrl(String raw) async {
    final String? normalized = normalizeSeatUrl(raw);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个地址看起来不对，应该以 https:// 开头并属于学习通或学校域名')),
      );
      return;
    }
    await _store.save(normalized);
    if (!mounted) return;
    setState(() => _url = normalized);
    await _openWebView(normalized);
  }

  Future<void> _forget() async {
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _url = null;
      _web = null;
      _progress = 0;
      _loadError = null;
    });
  }

  /// 没有地址时的兜底：一键跳到学习通 App，在里面手动点「座位预约」。
  ///
  /// 学习通没有公开的深链接文档，先试 `chaoxing://`，不行再退回网页版首页；
  /// 两个都起不来就提示用户自己去点图标——**不静默失败**。
  Future<void> _openChaoxingApp() async {
    for (final Uri target in <Uri>[
      Uri.parse('chaoxing://'),
      Uri.parse('https://i.chaoxing.com'),
    ]) {
      try {
        final bool ok = await launchUrl(
          target,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      } catch (_) {
        // 深链接不存在时 launchUrl 会抛 PlatformException，继续试下一个。
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没能拉起学习通，自己去桌面点开吧')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_url == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('座位预约')),
        body: _SetupBody(
          countdown: _countdown,
          onSubmit: _saveUrl,
          onOpenApp: _openChaoxingApp,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('座位预约'),
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _web?.reload(),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'copy') {
                Clipboard.setData(ClipboardData(text: _url!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('地址已复制')),
                );
              } else if (value == 'forget') {
                _forget();
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'copy', child: Text('复制地址')),
              PopupMenuItem<String>(value: 'forget', child: Text('换一个地址')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _RuleBanner(countdown: _countdown),
          if (_loadError != null)
            MaterialBanner(
              content: Text('页面加载失败：$_loadError'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    setState(() => _loadError = null);
                    _web?.reload();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: _web == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _web!),
          ),
        ],
      ),
    );
  }
}

extension _BoolOrTrue on bool? {
  bool get orTrue => this ?? true;
}

class _RuleBanner extends StatelessWidget {
  const _RuleBanner({required this.countdown});

  final String countdown;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.schedule, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              countdown,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupBody extends StatefulWidget {
  const _SetupBody({
    required this.countdown,
    required this.onSubmit,
    required this.onOpenApp,
  });

  final String countdown;
  final Future<void> Function(String raw) onSubmit;
  final Future<void> Function() onOpenApp;

  @override
  State<_SetupBody> createState() => _SetupBodyState();
}

class _SetupBodyState extends State<_SetupBody> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 学习通会把地址放进剪贴板的话，这一步就把「找不到链接」的活儿省了。
  Future<void> _pasteAndGo() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板里没有文字——先在学习通里复制那个页面的链接')),
      );
      return;
    }
    _controller.text = text;
    await _submit();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_controller.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        _RuleBanner(countdown: widget.countdown),
        const SizedBox(height: 20),
        Text('还差一个地址', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          '座位预约只在学习通 App 里有入口，网页版和电脑端都找不到，'
          '接口还要一串每校唯一的令牌。所以这一页做成「一次性粘地址，之后直接用」。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: widget.onOpenApp,
          icon: const Icon(Icons.open_in_new),
          label: const Text('先打开学习通'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pasteAndGo,
          icon: const Icon(Icons.content_paste),
          label: const Text('粘贴剪贴板里的地址'),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('怎么拿地址（三种，试到一个就行）',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                const Text('1. 学习通里打开「座位预约」，右上角「···」→ 复制链接'),
                const Text('2. 同一页「···」→ 在浏览器打开，再复制地址栏'),
                const Text('3. 长按页面里的文字 → 分享 → 复制链接'),
                const SizedBox(height: 8),
                Text(
                  '地址长这样：https://xxx.mh.chaoxing.com/engine2/general/more?t=...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 4,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '座位预约地址',
            hintText: 'https://…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check),
          label: const Text('保存并打开'),
        ),
        const SizedBox(height: 24),
        Text(
          '这一页只做跳转，不代你签到，也不改预约规则（22:00 开放次日、单次最长 15 小时）。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
