import 'dart:convert';

import 'package:crypto/crypto.dart';

/// URP（清元优软）登录密码变换。
///
/// 逐字还原自 `https://jwxs.tiangong.edu.cn/js/md5/md5.min.js` 与登录页按钮内联脚本：
///
/// ```js
/// function hex_md5(string, ver) {
///   string = md5_Utf8Encode(string + (ver === "1.8" ? "" : "{Urp602019}"));
///   ...
/// }
/// // 登录按钮 onclick：
/// j_password = hex_md5(hex_md5(pwd), '1.8') + '*' + hex_md5(hex_md5(pwd, '1.8'), '1.8');
/// ```
///
/// 展开后左右两半**并不相同**（右边少一次加盐），这是最容易写错的地方：
///
/// - 左：`MD5( MD5(pwd + "{Urp602019}") )`
/// - 右：`MD5( MD5(pwd) )`
/// - 结果：`左 + "*" + 右`
class UrpCrypto {
  UrpCrypto._();

  /// 服务端硬编码在 md5.min.js 里的盐值。
  static const String salt = '{Urp602019}';

  /// 标准 MD5 的十六进制小写表示。
  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  /// 对应 JS 的 `hex_md5(s, ver)`：
  /// `withSalt == true` 等价于 JS 不传第二个参数（追加盐）；
  /// `withSalt == false` 等价于 JS 传 `'1.8'`（不追加盐）。
  static String _hexMd5(String input, {required bool withSalt}) =>
      md5Hex(withSalt ? '$input$salt' : input);

  /// 生成表单字段 `j_password` 的值。
  ///
  /// 注意：JS 里的 UTF-8 编码器只处理 BMP（不含代理对），标准 `utf8.encode`
  /// 对绝大多数密码完全一致；含 emoji 等增补平面字符时两者会有差异。
  static String transformPassword(String password) {
    final String left = _hexMd5(
      _hexMd5(password, withSalt: true),
      withSalt: false,
    );
    final String right = _hexMd5(
      _hexMd5(password, withSalt: false),
      withSalt: false,
    );
    return '$left*$right';
  }
}
