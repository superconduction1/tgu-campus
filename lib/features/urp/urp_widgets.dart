import 'package:flutter/material.dart';

import '../../core/design.dart';
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
    final Color tint = expired ? TguColors.accents[3] : TguColors.sub;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                expired ? Icons.lock_clock_outlined : Icons.cloud_off_outlined,
                size: 28,
                color: tint,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              expired ? '登录已过期' : '没能取到数据',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: TguColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              expired ? '重新登录一次就好' : '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: TguColors.sub,
              ),
            ),
            const SizedBox(height: 20),
            if (expired && onRelogin != null) ...<Widget>[
              SizedBox(
                width: 156,
                child: FilledButton(
                  onPressed: onRelogin,
                  child: const Text('重新登录'),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('再试一次'),
              ),
            ] else
              SizedBox(
                width: 132,
                child: FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('重试'),
                ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: TguColors.sub.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: TguColors.sub),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: TguColors.ink,
              ),
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: TguColors.sub,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「这是缓存」的提示条。
///
/// 教务连不上的时候不白屏，退回去上次的数据，但必须说清楚：
/// 这不是刚从服务器拿到的，以及是什么时候的。
class UrpStaleBanner extends StatelessWidget {
  const UrpStaleBanner({
    super.key,
    required this.label,
    required this.onRetry,
  });

  /// 已经格式化好的时间，比如 `11-25 19:40`。
  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '教务连不上，显示 $label 的数据',
                style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

