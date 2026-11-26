import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/session.dart';
import '../chaoxing/seat_store.dart';
import '../diagnostics/checkup_page.dart';
import '../diagnostics/diagnostics.dart';
import '../login/login_page.dart';
import '../urp/urp_api.dart';

/// 设置页。
///
/// 这里只管三件事：看清现在存了什么、把某一摊登录信息清掉、确认这个 App
/// 到底把数据放哪儿了。所有存储都是本机的（`flutter_secure_storage`），
/// 没有任何服务端。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.store,
    this.embedded = false,
  });

  final UrpApi api;
  final SessionStore store;

  /// 嵌到底部 tab 里时不要自己的 AppBar。
  final bool embedded;

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

  /// 把作业列表原始 HTML 落到 App 私有目录，用来对着真实 DOM 校准解析器。
  Future<void> _exportCxWorkList() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在导出作业页…')));
    try {
      final String path = await Diagnostics(widget.api).exportCxWorkListDump();
      messenger.showSnackBar(SnackBar(content: Text('已存到 $path')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
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
    return Scaffold(
      backgroundColor: TguColors.page,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('我'),
              backgroundColor: TguColors.page,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: <Widget>[
                _Profile(
                  user: _urpUser.isEmpty ? '' : _mask(_urpUser),
                  online: _urpUser.isNotEmpty,
                ),
                const SectionTitle('账户'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _AccountRow(
                        icon: Icons.badge_outlined,
                        title: '教务系统',
                        subtitle: _urpUser.isEmpty
                            ? '未登录'
                            : '学号 ${_mask(_urpUser)}',
                        action: '退出',
                        onAction: _urpUser.isEmpty ? null : _forgetUrp,
                      ),
                      const _RowDivider(),
                      _AccountRow(
                        icon: Icons.school_outlined,
                        title: '学习通',
                        subtitle: _cxPhone.isEmpty
                            ? '未登录'
                            : '手机号 ${_mask(_cxPhone)}',
                        action: '清除',
                        onAction: _cxPhone.isEmpty ? null : _forgetCx,
                      ),
                      const _RowDivider(),
                      _AccountRow(
                        icon: Icons.event_seat_outlined,
                        title: '座位预约地址',
                        subtitle: _seatUrl.isEmpty
                            ? '还没保存'
                            : '已保存 · ${Uri.tryParse(_seatUrl)?.host ?? ''}',
                        action: '清除',
                        onAction: _seatUrl.isEmpty ? null : _forgetSeat,
                      ),
                    ],
                  ),
                ),
                const SectionTitle('工具'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AccentTile(
                    accent: TguColors.brand,
                    title: '运行自检',
                    meta: '逐个模块试一遍，连不上会写原因',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) =>
                            CheckupPage(api: widget.api),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: TguColors.sub,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AccentTile(
                    accent: TguColors.accents[1],
                    title: '导出学习通作业页',
                    meta: '把作业列表原始 HTML 存成文件，用来校准状态解析',
                    onTap: _exportCxWorkList,
                    trailing: const Icon(
                      Icons.file_download_outlined,
                      size: 18,
                      color: TguColors.sub,
                    ),
                  ),
                ),
                const SectionTitle('关于'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: TguColors.brand,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '天工校园',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: TguColors.ink,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '版本 0.1.0 · 个人自用',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: TguColors.sub,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '所有数据只存在这台手机上：学号密码、学习通账号、会话 Cookie '
                        '都放在系统的加密存储里，没有服务器，也不会上传。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: TguColors.sub,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '不做的事：不代做作业、不自动签到、不上架应用商店。'
                        '座位页只是把学校页面装进来，预约和退约都由你自己点。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: TguColors.sub,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '教务 URP 6.0（jwxs.tiangong.edu.cn）· 学习通：超星',
                        style: TextStyle(fontSize: 11.5, color: TguColors.sub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.user, required this.online});

  final String user;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TguColors.brand,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text(
              '天',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.isEmpty ? '未登录' : user,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: TguColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  online ? '天津工业大学 · 教务已连接' : '天津工业大学',
                  style: const TextStyle(fontSize: 12, color: TguColors.sub),
                ),
              ],
            ),
          ),
          SoftBadge(
            online ? '已登录' : '离线',
            color: online ? const Color(0xFF12A594) : TguColors.sub,
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: TguColors.sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: TguColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: TguColors.sub),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(action, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 45,
      endIndent: 14,
      color: TguColors.line,
    );
  }
}
