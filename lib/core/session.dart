import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'http.dart';

/// 读一个键，读不出来就当没存过。
///
/// `flutter_secure_storage` 在「重装应用、换签名、系统升级后 Keystore 主密钥
/// 失效」的时候会抛异常（解密失败）。这类异常如果不接住，会直接崩在启动闸门里，
/// 表现成白屏且无提示。debug 包每次重装签名都可能变，所以必须接：
/// 读失败 → 删掉这一条 → 当没登录过，用户重新登一次即可。
Future<String?> readOrClear(FlutterSecureStorage storage, String key) async {
  try {
    return await storage.read(key: key);
  } catch (_) {
    await deleteQuietly(storage, key);
    return null;
  }
}

/// 删一个键，删不掉也不让上层抛。
Future<void> deleteQuietly(FlutterSecureStorage storage, String key) async {
  try {
    await storage.delete(key: key);
  } catch (_) {
    // 删不掉时保持沉默：调用方要的是「它不在了」，再整体 clear 一次也是结果。
  }
}

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
    final String? username = await readOrClear(_storage, _kUsername);
    if (username == null || username.isEmpty) return null;
    return StoredCredentials(
      username: username,
      password: await readOrClear(_storage, _kPassword),
      cookies: await readOrClear(_storage, _kCookies),
    );
  }

  Future<void> clear() async {
    await deleteQuietly(_storage, _kUsername);
    await deleteQuietly(_storage, _kPassword);
    await deleteQuietly(_storage, _kCookies);
    await deleteQuietly(_storage, _kLastLogin);
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
    final String? phone = await readOrClear(_storage, _kPhone);
    final String? cookies = await readOrClear(_storage, _kCookies);
    // 网页登录只拿得到 Cookie、没有账号密码，这种情况也算已登录。
    final bool hasPhone = phone != null && phone.isNotEmpty;
    final bool hasCookies = cookies != null && cookies.isNotEmpty;
    if (!hasPhone && !hasCookies) return null;
    return StoredCxCredentials(
      phone: phone ?? '',
      password: await readOrClear(_storage, _kPassword),
      cookies: cookies,
    );
  }

  Future<void> clear() async {
    await deleteQuietly(_storage, _kPhone);
    await deleteQuietly(_storage, _kPassword);
    await deleteQuietly(_storage, _kCookies);
  }
}
