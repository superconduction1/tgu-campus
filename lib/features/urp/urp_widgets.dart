import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../login/login_page.dart';
import 'urp_api.dart';

/// 会话过期后唯一的出路：清掉本地凭据与 Cookie，回登录页重来。
///
/// 只给「登录已过期」用。网络错误重登录没有意义，重试就行。
Future<void> urpRelogin(BuildContext context, UrpApi api) async {
  final SessionStore store = SessionStore();
  // 先记住学号，登录页就能预填，省得手打。
  String? username;
  try {
    username = (await store.load())?.username;
  } catch (_) {
    username = null;
  }
  try {
    await store.clear();
  } catch (_) {
    // 清不掉也要能回登录页。
  }
  api.client.jar.clear();
  if (!context.mounted) return;
  await Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => LoginPage(
        api: api,
        store: store,
        initialUsername: username,
      ),
    ),
    (Route<dynamic> route) => false,
  );
}

/// 三个页面共用的错误显示。
///
/// 会话过期要跟「网络坏了」分开说——前者用户能自己解决，后者只能等。
class UrpErrorView extends StatelessWidget {
  const UrpErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.onRelogin,
  });

  final Object error;
  final VoidCallback onRetry;

  /// 会话过期时给一条真正能走通的路。
  final VoidCallback? onRelogin;

  @override
  Widget build(BuildContext context) {
    final bool expired = error is UrpSessionExpiredException;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              expired ? Icons.lock_clock_outlined : Icons.cloud_off_outlined,
              size: 44,
              color: scheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              expired ? '登录已过期' : '没能取到数据',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              expired ? '重新登录一次就好' : '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 20),
            if (expired && onRelogin != null) ...<Widget>[
              FilledButton(
                onPressed: onRelogin,
                child: const Text('重新登录'),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('再试一次'),
              ),
            ] else
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 空的、但原因值得说清楚的状态。
class UrpEmptyView extends StatelessWidget {
  const UrpEmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
