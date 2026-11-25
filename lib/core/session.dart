import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'http.dart';

/// 已保存的登录信息。
class StoredCredentials {
  const StoredCredentials({
    required this.username,
    required this.password,
    required this.cookies,
  });

  final String username;
  final String? password;
  final String? cookies;
}

/// 凭据存储。
///
/// 只落在 Android Keystore 里（`flutter_secure_storage` 默认走
/// EncryptedSharedPreferences / Keystore），不写明文文件、不打日志。
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _kUsername = 'urp.username';
  static const String _kPassword = 'urp.password';
  static const String _kCookies = 'urp.cookies';
  static const String _kLastLogin = 'urp.last_login';

  final FlutterSecureStorage _storage;

  Future<void> save({
    required String username,
    required String password,
    required CookieJar jar,
  }) async {
    await _storage.write(key: _kUsername, value: username);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kCookies, value: jar.export());
    await _storage.write(
      key: _kLastLogin,
      value: DateTime.now().toIso8601String(),
    );
  }

  /// 仅刷新 Cookie（例如长时间挂起后重新握手）。
  Future<void> saveCookies(CookieJar jar) =>
      _storage.write(key: _kCookies, value: jar.export());

  Future<StoredCredentials?> load() async {
    final String? username = await _storage.read(key: _kUsername);
    if (username == null || username.isEmpty) return null;
    return StoredCredentials(
      username: username,
      password: await _storage.read(key: _kPassword),
      cookies: await _storage.read(key: _kCookies),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kCookies);
    await _storage.delete(key: _kLastLogin);
  }
}

/// 学习通的登录信息。
class StoredCxCredentials {
  const StoredCxCredentials({
    required this.phone,
    this.password,
    this.cookies,
  });

  final String phone;
  final String? password;
  final String? cookies;
}

/// 学习通（超星）的会话存储。
///
/// 跟教务分开存：两个系统的登录态互不影响，一个掉了不该把另一个也清掉。
class CxSessionStore {
  CxSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _kPhone = 'cx.phone';
  static const String _kPassword = 'cx.password';
  static const String _kCookies = 'cx.cookies';

  final FlutterSecureStorage _storage;

  Future<void> save({
    required String phone,
    required String password,
    required CookieJar jar,
  }) async {
    await _storage.write(key: _kPhone, value: phone);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kCookies, value: jar.export());
  }

  Future<void> saveCookies(CookieJar jar) =>
      _storage.write(key: _kCookies, value: jar.export());

  Future<StoredCxCredentials?> load() async {
    final String? phone = await _storage.read(key: _kPhone);
    if (phone == null || phone.isEmpty) return null;
    return StoredCxCredentials(
      phone: phone,
      password: await _storage.read(key: _kPassword),
      cookies: await _storage.read(key: _kCookies),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _kPhone);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kCookies);
  }
}
