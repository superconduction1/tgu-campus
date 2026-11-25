import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/core/chaoxing_crypto.dart';

void main() {
  group('ChaoxingCrypto.encrypt', () {
    // 期望值由 Node 的 aes-128-cbc（key == iv，PKCS7）独立算出，
    // 与 login.js 里 CryptoJS 的参数一致。
    test('手机号', () {
      expect(
        ChaoxingCrypto.encrypt('13800138000'),
        'yYcVatS+4J+JGnm88UM56A==',
      );
    });

    test('带符号的密码', () {
      expect(
        ChaoxingCrypto.encrypt('Test@1234'),
        'NDq7emAD7il71U6Ba3I2fA==',
      );
    });

    test('学号形态', () {
      expect(
        ChaoxingCrypto.encrypt('2023123456'),
        'mKYmUkeaF8ngu21LtGHlyw==',
      );
    });

    test('单字符（检验 PKCS7 补位）', () {
      expect(
        ChaoxingCrypto.encrypt('a'),
        '8nF+VjieNCFu+PDbVN5etg==',
      );
    });

    test('相同明文结果稳定（IV 固定，不是随机 IV）', () {
      expect(
        ChaoxingCrypto.encrypt('13800138000'),
        ChaoxingCrypto.encrypt('13800138000'),
      );
    });
  });
}
