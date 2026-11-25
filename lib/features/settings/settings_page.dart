import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../chaoxing/seat_store.dart';
import '../login/login_page.dart';
import '../urp/urp_api.dart';

/// 设置页。
///
/// 这里只管三件事：看清现在存了什么、把某一摊登录信息清掉、确认这个 App
/// 到底把数据放哪儿了。所有存储都是本机的（`flutter_secure_storage`），
/// 没有任何服务端。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api, required this.store});

  final UrpApi api;
  final SessionStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  String _urpUser = '';
  String _cxPhone = '';
  String _seatUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String urpUser = '';
    String cxPhone = '';
    String seatUrl = '';
    try {
      urpUser = (await widget.store.load())?.username ?? '';
    } catch (_) {
      urpUser = '';
    }
    try {
      cxPhone = (await CxSessionStore().load())?.phone ?? '';
    } catch (_) {
      cxPhone = '';
    }
    try {
      seatUrl = await SeatLinkStore().load() ?? '';
    } catch (_) {
      seatUrl = '';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _urpUser = urpUser;
      _cxPhone = cxPhone;
      _seatUrl = seatUrl;
    });
  }

  /// 学号 2026123456 → 202****456；手机号 13812345678 → 138****5678。
  String _mask(String raw) {
    if (raw.length <= 4) return raw;
    if (raw.length <= 7) {
      return '${raw.substring(0, 1)}****${raw.substring(raw.length - 1)}';
    }
    return '${raw.substring(0, 3)}****${raw.substring(raw.length - 3)}';
  }

  Future<void> _forgetUrp() async {
    final bool ok = await _confirm('退出教务登录？', '下次打开需要重新输学号、密码和验证码。');
    if (!ok) return;
    await widget.store.clear();
    widget.api.client.jar.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginPage(api: widget.api, store: widget.store),
      ),
      (Route<void> route) => false,
    );
  }

  Future<void> _forgetCx() async {
    final bool ok = await _confirm('清除学习通登录？', '作业列表和座位页会需要重新登录学习通。');
    if (!ok) return;
    await CxSessionStore().clear();
    if (!mounted) return;
    await _load();
  }

  Future<void> _forgetSeat() async {
    final bool ok = await _confirm('清除座位预约地址？', '下次进座位页要重新粘一次那个链接。');
    if (!ok) return;
    await SeatLinkStore().clear();
    if (!mounted) return;
    await _load();
  }

  Future<bool> _confirm(String title, String body) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                _SectionHeader('账户'),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('教务系统'),
                  subtitle: Text(
                    _urpUser.isEmpty ? '未登录' : '学号 ${_mask(_urpUser)}',
                  ),
                  trailing: TextButton(
                    onPressed: _urpUser.isEmpty ? null : _forgetUrp,
                    child: const Text('退出'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('学习通'),
                  subtitle: Text(
                    _cxPhone.isEmpty ? '未登录' : '手机号 ${_mask(_cxPhone)}',
                  ),
                  trailing: TextButton(
                    onPressed: _cxPhone.isEmpty ? null : _forgetCx,
                    child: const Text('清除'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.event_seat_outlined),
                  title: const Text('座位预约地址'),
                  subtitle: Text(
                    _seatUrl.isEmpty ? '还没保存' : Uri.tryParse(_seatUrl)?.host ?? '已保存',
                  ),
                  trailing: TextButton(
                    onPressed: _seatUrl.isEmpty ? null : _forgetSeat,
                    child: const Text('清除'),
                  ),
                ),
                const Divider(height: 32),
                _SectionHeader('关于'),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('天工校园'),
                  subtitle: Text('版本 0.1.0 · 个人自用'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '所有数据只存在这台手机上：学号密码、学习通账号、会话 Cookie 都放在'
                    '系统的加密存储里，没有服务器，也不会上传。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '不做的事：不代做作业、不自动签到、不上架应用商店。'
                    '座位页只是把学校页面装进来，预约和退约都由你在页面里自己点。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '教务：URP 6.0（jwxs.tiangong.edu.cn）· 学习通：超星',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
