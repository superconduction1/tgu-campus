import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../home/home_page.dart';
import '../urp/urp_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.store,
    this.initialUsername,
  });

  final UrpApi api;
  final SessionStore store;
  final String? initialUsername;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _captcha = TextEditingController();

  String? _tokenValue;
  Uint8List? _captchaBytes;
  bool _loadingTicket = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.text = widget.initialUsername ?? '';
    _loadTicket();
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _loadTicket() async {
    setState(() {
      _loadingTicket = true;
      _captchaBytes = null;
      _tokenValue = null;
    });
    try {
      final LoginTicket ticket = await widget.api.loadLoginTicket();
      if (!mounted) return;
      setState(() {
        _tokenValue = ticket.tokenValue;
        _captchaBytes = ticket.captchaBytes;
        _loadingTicket = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTicket = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _submit() async {
    final String username = _user.text.trim();
    final String password = _password.text;
    final String captcha = _captcha.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写学号和密码');
      return;
    }
    if (captcha.length != 4) {
      setState(() => _error = '验证码是 4 位字符');
      return;
    }
    final String? token = _tokenValue;
    if (token == null) {
      setState(() => _error = '验证码还没取到，请点刷新');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final LoginOutcome outcome = await widget.api.login(
        username: username,
        password: password,
        captcha: captcha,
        tokenValue: token,
      );

      if (!outcome.success) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = outcome.message;
        });
        _captcha.clear();
        // 验证码一次性，失败必须换一张。
        await _loadTicket();
        return;
      }

      await widget.store.save(
        username: username,
        password: password,
        jar: widget.api.client.jar,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(api: widget.api, store: widget.store),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  Widget _buildCaptcha() {
    if (_loadingTicket) {
      return const SizedBox(
        width: 180,
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final Uint8List? bytes = _captchaBytes;
    if (bytes == null) {
      return SizedBox(
        width: 180,
        height: 60,
        child: TextButton(
          onPressed: _loadTicket,
          child: const Text('重试'),
        ),
      );
    }
    return InkWell(
      onTap: _loadTicket,
      child: Image.memory(
        bytes,
        width: 180,
        height: 60,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.school, size: 64, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    '天津工业大学',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '高校教学管理与服务平台',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _user,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _captcha,
                          maxLength: 4,
                          decoration: const InputDecoration(
                            labelText: '验证码',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildCaptcha(),
                    ],
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登 录'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '账号密码只保存在本机 Keystore，不上传任何服务器。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
