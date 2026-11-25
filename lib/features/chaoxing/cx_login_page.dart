import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/http.dart';
import '../../core/session.dart';
import 'cx_api.dart';
import 'cx_parser.dart';
import 'models.dart';

/// 学习通网页登录：让用户在内嵌 WebView 里自己登一次，再把 Cookie 收回来。
///
/// 为什么要有这条路：学习通账号体系里手机号和学号并存，有的账号还要求
/// 短信验证码，光靠「账号 + 密码」两个输入框很容易卡住（实测用学号会
/// 直接回「用户名或密码错误」）。走网页登录则完全复用官方页面，验证码、
/// 滑块、短信都由官方页面自己处理，登完把 Cookie 交给 App 就够了。
class CxLoginPage extends StatefulWidget {
  const CxLoginPage({super.key});

  /// 学习通默认登录页，`fid=2276` 是天工大的机构号。
  static final Uri entry = Uri.parse(
    'https://passport2.chaoxing.com/login?fid=2276&refer=https%3A%2F%2Fi.chaoxing.com',
  );

  @override
  State<CxLoginPage> createState() => _CxLoginPageState();
}

class _CxLoginPageState extends State<CxLoginPage> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookies = WebViewCookieManager();

  int _progress = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int value) {
            if (mounted) setState(() => _progress = value);
          },
          onWebResourceError: (WebResourceError error) {
            // 主框架导航失败才算问题；图片/脚本失败很常见。
            if (error.isForMainFrame != false && mounted) {
              setState(() => _error = '页面加载失败：${error.description}');
            }
          },
        ),
      );
    unawaited(_controller.loadRequest(CxLoginPage.entry));
  }

  /// 从 WebView 的 Cookie 罐里把学习通各域的 Cookie 收出来。
  ///
  /// 官方页面在 passport2 域下发登录票据，再跳回 i.chaoxing.com；
  /// 两个域的 Cookie 都要，缺任意一个后续请求都会被判未登录。
  Future<Map<String, String>> _harvest() async {
    const List<String> hosts = <String>[
      'https://passport2.chaoxing.com',
      'https://i.chaoxing.com',
      'https://mooc1.chaoxing.com',
      'https://mooc2-ans.chaoxing.com',
    ];
    final Map<String, String> merged = <String, String>{};
    for (final String host in hosts) {
      try {
        final List<WebViewCookie> list = await _cookies.getCookies(
          domain: Uri.parse(host),
        );
        for (final WebViewCookie c in list) {
          if (c.name.isEmpty) continue;
          merged[c.name] = c.value;
        }
      } catch (_) {
        // 某个域取不到不影响其它域。
      }
    }
    return merged;
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, String> harvested = await _harvest();
      if (harvested.isEmpty) {
        setState(() => _error = '没拿到学习通 Cookie，先在页面里登录完再点这里');
        return;
      }

      // 真拿一次课程列表验收：Cookie 不全或过期会在这里暴露。
      final SchoolHttpClient client = SchoolHttpClient();
      client.jar.restore(jsonEncode(harvested));
      final List<CxCourse> courses = await ChaoxingApi(client).fetchCourses();
      if (courses.isEmpty) {
        setState(() => _error = '登录状态还没生效，课程列表是空的，再试一次');
        return;
      }

      final StoredCxCredentials? old = await CxSessionStore().load();
      await CxSessionStore().save(
        phone: old?.phone ?? '',
        password: old?.password ?? '',
        jar: client.jar,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CxDeniedException {
      // 最常见的失败：用户还没登进去就点了按钮，课程列表被 302 回登录页。
      if (mounted) {
        setState(() => _error = '还没登录成功：先在上面的页面里扫码或输验证码，'
            '看到课程列表之后再点这个按钮');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '验收失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页登录学习通'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100)
          else
            const SizedBox(height: 4),
          Expanded(child: WebViewWidget(controller: _controller)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 46,
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : () => unawaited(_finish()),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录好了，把登录态收回来'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
