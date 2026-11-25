import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 座位预约入口地址的存储。
///
/// 这个应用挂在学习通 App 里，网页/桌面版根本没有入口，
/// 所以只能让用户自己粘一次完整地址（形如
/// `https://xxx.mh.chaoxing.com/engine2/general/more?t=...`）。
/// 保存后用内置 WebView 打开，预约 / 退约 / 看记录都在那个页面里做。
class SeatLinkStore {
  SeatLinkStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _kUrl = 'seat.url';

  final FlutterSecureStorage _storage;

  Future<String?> load() async {
    final String? url = await _storage.read(key: _kUrl);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> save(String url) => _storage.write(key: _kUrl, value: url);

  Future<void> clear() => _storage.delete(key: _kUrl);
}
