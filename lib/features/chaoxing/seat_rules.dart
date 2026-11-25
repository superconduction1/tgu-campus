/// 图书馆座位预约的时间规则（纯 Dart，方便单测）。
///
/// 学校的规矩：**每天 22:00 开放次日座位**，单次最长 15 小时，
/// 每天最多取消 3 次，每周违约 3 次停用一周。
/// 这里只负责「现在能不能约 / 距下一次开放还有多久」，
/// 真正的预约动作走学习通里的那个 H5 页面，不自动签到。
library;

/// 每晚开放时刻（小时，24 小时制）。
const int seatOpenHour = 22;

/// 下一次开放的整点（当天或次日 22:00）。
DateTime nextSeatOpen(DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day, seatOpenHour);
  if (now.isBefore(today)) return today;
  if (now.isAtSameMomentAs(today)) return now;
  return today.add(const Duration(days: 1));
}

/// 现在是否已经过了当天 22:00（今天的这一轮是否已经开始）。
bool seatOpenNow(DateTime now) => now.hour >= seatOpenHour;

/// 距下一次开放还有多久；正好卡在开放时刻返回 [Duration.zero]。
Duration untilSeatOpen(DateTime now) => nextSeatOpen(now).difference(now);

/// 给界面用的一句话。
String seatCountdownLabel(DateTime now) {
  if (seatOpenNow(now)) return '今天 22:00 已开放，可约明天的座位';
  final Duration d = untilSeatOpen(now);
  if (d.inMinutes <= 0) return '马上就要开放了';
  final int hours = d.inHours;
  final int minutes = d.inMinutes % 60;
  if (hours > 0) return '距 22:00 开放还有 $hours 小时 $minutes 分';
  return '距 22:00 开放还有 $minutes 分';
}

/// 允许的域名后缀：学习通的各个域，以及学校自己的域名。
const List<String> allowedSeatHostSuffixes = <String>[
  'chaoxing.com',
  'chaoxing.cn',
  'tiangong.edu.cn',
];

/// 校验并清理用户粘进来的地址，合法才返回，否则 null。
///
/// 规则：必须是 http/https、必须有主机名、主机名必须落在
/// [allowedSeatHostSuffixes] 之内（按「本身或子域」匹配，
/// 免得 `evilchaoxing.com` 这种混进来）。
/// 没写协议的常见情况（`xxx.mh.chaoxing.com/engine2/...`）会自动补 `https://`。
String? normalizeSeatUrl(String input) {
  String s = input.trim();
  if (s.isEmpty) return null;
  // 从聊天软件复制常带首尾引号或尖括号
  const List<String> wrappers = <String>['"', "'", '<', '>', '`'];
  for (final String w in wrappers) {
    if (s.startsWith(w)) s = s.substring(1).trim();
    if (s.endsWith(w)) s = s.substring(0, s.length - 1).trim();
  }
  if (s.isEmpty) return null;
  final String lower = s.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    if (s.contains('.') && !s.contains(' ')) {
      s = 'https://$s';
    } else {
      return null;
    }
  }
  final Uri? uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  final String host = uri.host.toLowerCase();
  final bool ok = allowedSeatHostSuffixes
      .any((String suffix) => host == suffix || host.endsWith('.$suffix'));
  if (!ok) return null;
  return uri.toString();
}

/// 二级公共后缀：这些不能当 Cookie 域（浏览器会直接拒掉）。
const Set<String> _twoLabelPublicSuffixes = <String>{
  'edu.cn',
  'com.cn',
  'net.cn',
  'org.cn',
  'gov.cn',
  'ac.cn',
  'com.hk',
  'edu.hk',
  'org.hk',
  'co.uk',
  'org.uk',
  'ac.uk',
  'co.jp',
  'ac.jp',
  'com.tw',
  'edu.tw',
  'com.sg',
  'edu.sg',
};

/// 给 WebView 注入 Cookie 时该写哪些域。
///
/// 座位页在 `*.mh.chaoxing.com` 上，但它自己会去 `passport2.chaoxing.com`、
/// `mooc1.chaoxing.com` 这些兄弟域取登录态，所以同一个 Cookie 要按
/// 「精确主机 + 逐级父域」各写一份。本地 Cookie 罐不记录域，
/// 这里只能按加载地址反推；公共后缀（`edu.cn`）要跳过，
/// 否则浏览器会拒绝这条 Cookie。
List<String> cookieDomainsFor(String host) {
  final String h = host.trim().toLowerCase();
  if (h.isEmpty) return const <String>[];
  final List<String> labels =
      h.split('.').where((String s) => s.isNotEmpty).toList();
  // localhost / 10.0.0.1 这类没有父域可加。
  if (labels.length < 2) return <String>[h];
  final List<String> out = <String>[h];
  for (int i = 1; i <= labels.length - 2; i++) {
    final List<String> rest = labels.sublist(i);
    if (rest.length == 2 && _twoLabelPublicSuffixes.contains(rest.join('.'))) {
      break;
    }
    out.add('.${rest.join('.')}');
  }
  return out;
}

/// 从地址里取主机名，取不到返回空串。
String hostOfUrl(String url) => Uri.tryParse(url.trim())?.host ?? '';

