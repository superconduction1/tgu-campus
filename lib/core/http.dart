import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'text_decode.dart';

/// 极简 Cookie 容器。
///
/// URP 是 Spring Security + 网关粘性路由，必须完整回传
/// `student.urpSoft.cn` / `route` / `JSESSIONID` 三个 Cookie，缺一个就会
/// 出现「验证码永远错」或「登录后立刻掉线」。
class CookieJar {
  final Map<String, String> _jar = <String, String>{};

  void absorb(Iterable<String> setCookieHeaders) {
    for (final String raw in setCookieHeaders) {
      final int semicolon = raw.indexOf(';');
      final String pair = semicolon == -1 ? raw : raw.substring(0, semicolon);
      final int equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final String name = pair.substring(0, equals).trim();
      final String value = pair.substring(equals + 1).trim();
      if (name.isEmpty) continue;
      _jar[name] = value;
    }
  }

  String get header => _jar.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');

  bool get isEmpty => _jar.isEmpty;

  Map<String, String> get entries => Map<String, String>.unmodifiable(_jar);

  String export() => jsonEncode(_jar);

  void restore(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        _jar
          ..clear()
          ..addAll(decoded.map((String k, dynamic v) =>
              MapEntry<String, String>(k, v.toString())));
      }
    } on FormatException {
      // 存档损坏就当作没登录，走重新登录流程。
    }
  }

  void clear() => _jar.clear();
}

/// 一次 HTTP 响应的快照。
class HttpResult {
  HttpResult({
    required this.statusCode,
    required this.headers,
    required this.setCookies,
    required this.bodyBytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<String> setCookies;
  final Uint8List bodyBytes;

  String get body => const Utf8Decoder(allowMalformed: true).convert(bodyBytes);

  /// 按真实编码解出来的 HTML。学习通有些页面是 GBK，用 [body] 会得到乱码，
  /// 解析学习通页面时一律用这个。
  String get html => decodeHtmlBytes(
        bodyBytes,
        declaredCharset: charsetOf(headers[HttpHeaders.contentTypeHeader]),
      );

  String? get location => headers[HttpHeaders.locationHeader];

  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  int get length => bodyBytes.length;
}

/// 面向校园系统的 HTTP 客户端：手动管理重定向与 Cookie。
///
/// 不用 dio 是刻意的——登录流程必须「看到 302 的 Location 才能判断
/// 是 badCaptcha 还是成功」，自动跟随重定向会把这条信息吃掉。
class SchoolHttpClient {
  SchoolHttpClient({CookieJar? cookieJar}) : jar = cookieJar ?? CookieJar() {
    _client
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 10)
      ..autoUncompress = true;
  }

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  final CookieJar jar;
  final HttpClient _client = HttpClient();

  Future<HttpResult> get(Uri uri, {Map<String, String>? headers}) =>
      _send('GET', uri, headers: headers);

  Future<HttpResult> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String>? headers,
  }) =>
      _send('POST', uri, form: form, headers: headers);

  Future<HttpResult> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Map<String, String>? headers,
  }) async {
    final HttpClientRequest request = await _client.openUrl(method, uri);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.userAgentHeader, userAgent)
      ..headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');

    headers?.forEach((String key, String value) {
      request.headers.set(key, value);
    });

    final String cookieHeader = jar.header;
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }

    if (form != null) {
      final String body = form.entries
          .map((MapEntry<String, String> e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final List<int> bytes = utf8.encode(body);
      request.headers
        ..set(HttpHeaders.contentTypeHeader,
            'application/x-www-form-urlencoded; charset=UTF-8')
        ..set(HttpHeaders.contentLengthHeader, bytes.length.toString());
      request.add(bytes);
    }

    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 25));

    final List<String> setCookies =
        response.headers[HttpHeaders.setCookieHeader] ?? <String>[];
    jar.absorb(setCookies);

    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }

    final Map<String, String> responseHeaders = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      responseHeaders[name.toLowerCase()] = values.join(', ');
    });

    return HttpResult(
      statusCode: response.statusCode,
      headers: responseHeaders,
      setCookies: setCookies,
      bodyBytes: builder.takeBytes(),
    );
  }

  void close() => _client.close(force: true);
}
