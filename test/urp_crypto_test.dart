import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/core/urp_crypto.dart';

void main() {
  group('md5Hex 标准向量', () {
    test('空串', () {
      expect(UrpCrypto.md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
    });

    test('abc', () {
      expect(UrpCrypto.md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('transformPassword 与服务端 JS 等价', () {
    // 期望值由 md5.min.js 的语义独立实算得出：
    //   left  = MD5( MD5(pwd + "{Urp602019}") )
    //   right = MD5( MD5(pwd) )
    //   result = left + "*" + right
    test('123456', () {
      expect(
        UrpCrypto.transformPassword('123456'),
        'ca1b3db944006232ca6c5f3e8137c271*14e1b600b1fd579f47433b88e8d85291',
      );
    });

    test('Abc@2024', () {
      expect(
        UrpCrypto.transformPassword('Abc@2024'),
        'a7679235aa40672a823498957f7cee2f*28b19fe3d2f30bb461c58c3bfd46ca20',
      );
    });

    test('tgu2026', () {
      expect(
        UrpCrypto.transformPassword('tgu2026'),
        '71fa93cc8f3941faa922e27ea970c3f9*ea51a677409b1caff667bb55815779c4',
      );
    });

    test('左右两半必须不同（右边少一次加盐）', () {
      final List<String> halves =
          UrpCrypto.transformPassword('123456').split('*');
      expect(halves, hasLength(2));
      expect(halves[0], isNot(equals(halves[1])));
    });
  });
}
