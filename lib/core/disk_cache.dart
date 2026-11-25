/// 把「上次成功拿到的数据」落到磁盘，网络不通时用来兜底。
///
/// 只依赖 `dart:io`，目录由调用方注入（App 里传 `path_provider`，
/// 断言脚手架里传临时目录），所以这一层能直接测。
library;

import 'dart:io';

import 'snapshot.dart';

class DiskCache {
  DiskCache(this.directory, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// 缓存根目录。允许抛异常——调用方要自己兜住（取目录本身也可能失败）。
  final Future<Directory> Function() directory;

  final DateTime Function() _now;

  /// 写不进去就算了，不能因为缓存把正常流程搞挂。
  Future<bool> save(String key, String value) async {
    try {
      final File file = await _fileFor(key);
      final String encoded = encodeSnapshot(
        CachedSnapshot(value: value, savedAt: _now()),
      );
      await file.writeAsString(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<CachedSnapshot?> load(String key) async {
    try {
      final File file = await _fileFor(key);
      if (!await file.exists()) return null;
      return decodeSnapshot(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    try {
      final File file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉也无所谓，下次写会覆盖。
    }
  }

  /// 退出登录 / 换账号时清干净。
  Future<void> clear() async {
    try {
      final Directory dir = await _dir();
      if (!await dir.exists()) return;
      await for (final FileSystemEntity entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 单个删不掉跳过。
        }
      }
    } catch (_) {
      // 整体失败就算了。
    }
  }

  Future<Directory> _dir() async {
    final Directory root = await directory();
    final Directory dir = Directory('${root.path}${Platform.pathSeparator}tgu_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String key) async {
    final Directory dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}'
        '${sanitizeCacheKey(key)}.json');
  }
}
