import 'package:flutter/material.dart';

import 'core/http.dart';
import 'core/session.dart';
import 'features/shell/home_shell.dart';
import 'features/login/login_page.dart';
import 'features/urp/urp_api.dart';

/// 学校主题色，取自教务登录页背景 `#71246b`。
const Color kSchoolPurple = Color(0xFF71246B);

void main() {
  runApp(const TguCampusApp());
}

class TguCampusApp extends StatelessWidget {
  const TguCampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '天工校园',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kSchoolPurple),
      ),
      home: const BootGate(),
    );
  }
}

/// 启动闸门：能用存下来的 Cookie 免登录就直接进首页，否则回登录页。
class BootGate extends StatefulWidget {
  const BootGate({super.key});

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  final SessionStore _store = SessionStore();
  final SchoolHttpClient _http = SchoolHttpClient();
  late final UrpApi _api = UrpApi(_http);

  bool _checking = true;
  String? _prefillUsername;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    StoredCredentials? credentials;
    try {
      credentials = await _store.load();
    } catch (_) {
      credentials = null;
    }

    if (credentials != null) {
      _prefillUsername = credentials.username;
      _http.jar.restore(credentials.cookies);
      try {
        final Object? landing = await _api.probeLanding();
        if (landing != null && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => HomeShell(api: _api, store: _store),
            ),
          );
          return;
        }
      } catch (_) {
        // 网络不通就先回登录页，不阻塞启动。
      }
    }

    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LoginPage(
      api: _api,
      store: _store,
      initialUsername: _prefillUsername,
    );
  }
}
