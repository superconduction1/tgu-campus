import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 学习通（超星）登录密码的传输加密。
///
/// 逆向自 `passport2-static.chaoxing.com/js/fanya/login.js`：
///
/// ```js
/// function encryptByAES(message, key) {
///   let CBCOptions = { iv: CryptoJS.enc.Utf8.parse(key),
///                      mode: CryptoJS.mode.CBC,
///                      padding: CryptoJS.pad.Pkcs7 };
///   let aeskey = CryptoJS.enc.Utf8.parse(key);
///   let secretData = CryptoJS.enc.Utf8.parse(message);
///   return CryptoJS.enc.Base64.stringify(
///     CryptoJS.AES.encrypt(secretData, aeskey, CBCOptions).ciphertext);
/// }
/// ```
///
/// 三个要点，少一个都对不上：
/// - 密钥和 IV **是同一个值**，都是 UTF-8 编码的 16 字节字符串（AES-128）
/// - 模式 CBC，填充 PKCS7
/// - 输出是 `ciphertext` 的 Base64，**不含** `Salted__` 前缀
///
/// 另外注意：是否加密由页面上的 `#t` 决定，`t == "true"` 才加密。
/// 2026-11 实测该值为 `"true"`，但代码里仍按运行时读取处理。
class ChaoxingCrypto {
  ChaoxingCrypto._();

  /// 硬编码在 login.js 里的传输密钥。
  static const String transferKey = 'u2oh6Vu^HWe4_AES';

  static String encrypt(String plain, {String key = transferKey}) {
    final Uint8List keyBytes = Uint8List.fromList(utf8.encode(key));
    final PaddedBlockCipher cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(keyBytes),
                keyBytes,
              ),
              null,
            ),
          );

    final Uint8List encrypted =
        cipher.process(Uint8List.fromList(utf8.encode(plain)));
    return base64Encode(encrypted);
  }
}
