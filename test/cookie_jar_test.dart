import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/core/http.dart';

void main() {
  group('CookieJar', () {
    test('吸收多条 Set-Cookie 并拼接请求头', () {
      final CookieJar jar = CookieJar();
      jar.absorb(<String>[
        'student.urpSoft.cn=aaaXovXGixw7HgM; path=/; Secure; HttpOnly',
        'route=70bd6155b9b4975f; Path=/',
      ]);

      expect(
        jar.header,
        'student.urpSoft.cn=aaaXovXGixw7HgM; route=70bd6155b9b4975f',
      );
    });

    test('同名 Cookie 后者覆盖前者', () {
      final CookieJar jar = CookieJar();
      jar.absorb(<String>['JSESSIONID=old; Path=/']);
      jar.absorb(<String>['JSESSIONID=new; Path=/']);
      expect(jar.header, 'JSESSIONID=new');
    });

    test('export / restore 往返一致', () {
      final CookieJar jar = CookieJar();
      jar.absorb(<String>['a=1; Path=/', 'b=2; Path=/']);
      final String payload = jar.export();

      final CookieJar restored = CookieJar()..restore(payload);
      expect(restored.entries, jar.entries);
    });

    test('损坏的存档不抛异常', () {
      final CookieJar jar = CookieJar()..restore('{not json');
      expect(jar.isEmpty, isTrue);
    });

    test('空 Set-Cookie 被忽略', () {
      final CookieJar jar = CookieJar()
        ..absorb(<String>['', '=nokey', 'novalue']);
      expect(jar.isEmpty, isTrue);
    });
  });
}
