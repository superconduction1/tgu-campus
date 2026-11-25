import 'package:flutter/material.dart';

import '../../core/http.dart';
import '../../core/session.dart';
import 'cx_api.dart';
import 'cx_parser.dart';
import 'homework_detail_page.dart';
import 'models.dart';

/// 作业页。
///
/// 学习通的登录态跟教务是分开的，所以这个页面自己管理会话：
/// 首次进来要求输入学习通手机号 + 密码，之后从 [CxSessionStore] 恢复 Cookie。
class HomeworkPage extends StatefulWidget {
  const HomeworkPage({super.key});

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  final CxSessionStore _store = CxSessionStore();
  final ChaoxingApi _api = ChaoxingApi(SchoolHttpClient());

  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _booting = true;
  bool _loggedIn = false;
  bool _busy = false;
  String? _error;
  String? _loginError;
  HomeworkList? _data;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    StoredCxCredentials? saved;
    try {
      saved = await _store.load();
    } catch (_) {
      saved = null;
    }
    if (saved != null) {
      _phone.text = saved.phone;
      _api.client.jar.restore(saved.cookies);
    }
    if (!mounted) return;
    setState(() {
      _booting = false;
      _loggedIn = saved?.cookies != null && saved!.cookies!.isNotEmpty;
    });
    if (_loggedIn) await _refresh();
  }

  Future<void> _login() async {
    final String phone = _phone.text.trim();
    final String password = _password.text;
    if (phone.isEmpty || password.isEmpty) {
      setState(() => _loginError = '手机号和密码都要填');
      return;
    }

    setState(() {
      _busy = true;
      _loginError = null;
    });

    try {
      final CxLoginOutcome outcome =
          await _api.login(phone: phone, password: password);
      if (!outcome.success) {
        if (!mounted) return;
        setState(() => _loginError = outcome.message ?? '登录失败');
        return;
      }

      // 登录接口给的跳转地址带着会话参数，跟一次能把 Cookie 补全。
      final String? redirect = outcome.redirect;
      if (redirect != null && redirect.isNotEmpty) {
        try {
          await _api.client.get(Uri.parse(redirect));
        } catch (_) {
          // 跳转打不开不影响，后面拉作业列表时还会暴露真实错误。
        }
      }

      await _store.save(
        phone: phone,
        password: password,
        jar: _api.client.jar,
      );

      if (!mounted) return;
      setState(() => _loggedIn = true);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loginError = '登录出错：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HomeworkList list = await _api.fetchHomework();
      if (!mounted) return;
      setState(() => _data = list);
      await _store.saveCookies(_api.client.jar);
    } on CxDeniedException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '拉取作业失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _logout() {
    _api.client.jar.clear();
    _store.clear();
    setState(() {
      _loggedIn = false;
      _data = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作业'),
        actions: <Widget>[
          if (_loggedIn)
            IconButton(
              tooltip: '刷新',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          if (_loggedIn)
            IconButton(
              tooltip: '退出学习通',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_loggedIn) {
      return _LoginForm(
        phone: _phone,
        password: _password,
        busy: _busy,
        error: _loginError,
        onSubmit: _login,
      );
    }

    final HomeworkList? data = _data;
    if (data == null && _busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data == null) {
      return _ErrorView(message: _error ?? '没有拿到数据', onRetry: _refresh);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            _ErrorView(message: _error!, onRetry: _refresh),
            const SizedBox(height: 12),
          ],
          if (data.isEmpty)
            const _EmptyView()
          else
            ..._buildGrouped(data),
          if (data.failures.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              '有 ${data.failedCount} 门课没取到：',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            for (final String f in data.failures)
              Text('· $f', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  /// 按课程分组，未交的排前面。
  List<Widget> _buildGrouped(HomeworkList list) {
    final Map<String, List<HomeworkItem>> byCourse =
        <String, List<HomeworkItem>>{};
    for (final HomeworkItem item in list.items) {
      byCourse.putIfAbsent(item.courseName, () => <HomeworkItem>[]).add(item);
    }
    final List<String> names = byCourse.keys.toList()
      ..sort((String a, String b) {
        final int pa = byCourse[a]!.where((HomeworkItem e) => e.isPending).length;
        final int pb = byCourse[b]!.where((HomeworkItem e) => e.isPending).length;
        if (pa != pb) return pb.compareTo(pa);
        return a.compareTo(b);
      });

    return <Widget>[
      for (final String name in names) ...<Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name.isEmpty ? '未标注课程' : name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${byCourse[name]!.where((HomeworkItem e) => e.isPending).length}'
                '/${byCourse[name]!.length} 待交',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        for (final HomeworkItem item in byCourse[name]!)
          _HomeworkTile(item: item),
        const SizedBox(height: 4),
      ],
    ];
  }
}

class _HomeworkTile extends StatelessWidget {
  const _HomeworkTile({required this.item});

  final HomeworkItem item;

  Color _color(ColorScheme scheme) => switch (item.status) {
        HomeworkStatus.notSubmitted => scheme.error,
        HomeworkStatus.grading => scheme.tertiary,
        HomeworkStatus.submitted => scheme.primary,
        HomeworkStatus.graded => scheme.secondary,
        HomeworkStatus.expired => scheme.outline,
        HomeworkStatus.unknown => scheme.outline,
      };

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = _color(scheme);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.deadline.isEmpty
            ? null
            : Text('截止 ${item.deadline}',
                style: Theme.of(context).textTheme.bodySmall),
        onTap: item.url.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HomeworkDetailPage(item: item),
                  ),
                ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.statusText.isEmpty ? item.status.label : item.statusText,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
            if (item.url.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.chevron_right, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.phone,
    required this.password,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController phone;
  final TextEditingController password;
  final bool busy;
  final String? error;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: <Widget>[
        const Icon(Icons.assignment_ind_outlined, size: 56),
        const SizedBox(height: 12),
        Text(
          '学习通账号',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '作业和座位预约都在学习通里，这里单独登录一次。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => busy ? null : onSubmit(),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录学习通'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.task_alt,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('没有作业'),
          ],
        ),
      ),
    );
  }
}
