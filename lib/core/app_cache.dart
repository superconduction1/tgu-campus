import 'package:path_provider/path_provider.dart';

import 'disk_cache.dart';

/// App 里用的缓存实例。
///
/// 文件放在应用私有目录（`getApplicationDocumentsDirectory`），
/// 卸载即清，不会被别的 App 看到，也不进备份以外的任何地方。
DiskCache appCache() => DiskCache(getApplicationDocumentsDirectory);

/// 缓存 key 全集。用常量，避免各页面各写一个字符串写岔。
class CacheKeys {
  const CacheKeys._();

  static const String timetable = 'urp.timetable';
  static const String scores = 'urp.scores';
  static const String exams = 'urp.exams';
}
