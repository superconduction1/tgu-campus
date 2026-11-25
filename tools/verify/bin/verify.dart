// 纯 Dart 校验：不依赖 Flutter，只验证 core 层的算法与数据结构。
//
// 用法（在 tools/verify 目录下）：
//   dart pub get
//   dart run bin/verify.dart

import 'dart:convert';
import 'dart:io';

import 'package:gbk_codec/gbk_codec.dart';

import '../../../lib/core/chaoxing_crypto.dart';
import '../../../lib/core/html_table.dart';
import '../../../lib/core/http.dart';
import '../../../lib/core/text_decode.dart';
import '../../../lib/core/urp_crypto.dart';
import '../../../lib/features/chaoxing/cx_parser.dart';
import '../../../lib/features/chaoxing/models.dart';
import '../../../lib/features/chaoxing/seat_rules.dart';
import '../../../lib/features/urp/models.dart';
import '../../../lib/features/urp/score_stats.dart';
import '../../../lib/features/urp/timetable_grid.dart';
import '../../../lib/features/urp/today.dart';
import '../../../lib/features/urp/urp_api.dart';
import '../../../lib/features/urp/urp_parser.dart';

int _passed = 0;
int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if ('$actual' == '$expected') {
    _passed++;
    stdout.writeln('  PASS  $name');
  } else {
    _failed++;
    stdout.writeln('  FAIL  $name');
    stdout.writeln('        期望: $expected');
    stdout.writeln('        实际: $actual');
  }
}

void main() {
  stdout.writeln('\n[1] URP 密码变换（对照 md5.min.js 语义）');
  check(
    '123456',
    UrpCrypto.transformPassword('123456'),
    'ca1b3db944006232ca6c5f3e8137c271*14e1b600b1fd579f47433b88e8d85291',
  );
  check(
    'Abc@2024',
    UrpCrypto.transformPassword('Abc@2024'),
    'a7679235aa40672a823498957f7cee2f*28b19fe3d2f30bb461c58c3bfd46ca20',
  );
  check(
    'tgu2026',
    UrpCrypto.transformPassword('tgu2026'),
    '71fa93cc8f3941faa922e27ea970c3f9*ea51a677409b1caff667bb55815779c4',
  );
  final List<String> halves = UrpCrypto.transformPassword('123456').split('*');
  check('左右两半不对称', halves.length == 2 && halves[0] != halves[1], true);

  stdout.writeln('\n[2] URP md5 标准向量');
  check('md5("")', UrpCrypto.md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
  check('md5("abc")', UrpCrypto.md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');

  stdout.writeln('\n[3] 学习通 AES-CBC 传输加密（对照 CryptoJS 参数）');
  check('13800138000', ChaoxingCrypto.encrypt('13800138000'), 'yYcVatS+4J+JGnm88UM56A==');
  check('Test@1234', ChaoxingCrypto.encrypt('Test@1234'), 'NDq7emAD7il71U6Ba3I2fA==');
  check('2023123456', ChaoxingCrypto.encrypt('2023123456'), 'mKYmUkeaF8ngu21LtGHlyw==');
  check('a', ChaoxingCrypto.encrypt('a'), '8nF+VjieNCFu+PDbVN5etg==');
  check(
    '固定 IV 结果稳定',
    ChaoxingCrypto.encrypt('13800138000') ==
        ChaoxingCrypto.encrypt('13800138000'),
    true,
  );

  stdout.writeln('\n[4] CookieJar');
  final CookieJar jar = CookieJar()
    ..absorb(<String>[
      'student.urpSoft.cn=aaaXovXGixw7HgM; path=/; Secure; HttpOnly',
      'route=70bd6155b9b4975f; Path=/',
    ]);
  check(
    '多条 Set-Cookie 拼接',
    jar.header,
    'student.urpSoft.cn=aaaXovXGixw7HgM; route=70bd6155b9b4975f',
  );

  final CookieJar overwrite = CookieJar()
    ..absorb(<String>['JSESSIONID=old; Path=/'])
    ..absorb(<String>['JSESSIONID=new; Path=/']);
  check('同名覆盖', overwrite.header, 'JSESSIONID=new');

  final CookieJar roundTrip = CookieJar()..restore(jar.export());
  check('export/restore 往返', roundTrip.header, jar.header);

  final CookieJar broken = CookieJar()..restore('{not json');
  check('损坏存档不抛异常', broken.isEmpty, true);

  final CookieJar junk = CookieJar()..absorb(<String>['', '=nokey', 'novalue']);
  check('空 / 畸形 Cookie 被忽略', junk.isEmpty, true);

  stdout.writeln('\n[5] HTML 表格提取（含 rowspan / 布局表格干扰）');
  const String page = '''
<html><body>
<table class="layout"><tr><td>导航</td><td>欢迎</td></tr></table>
<table class="data">
  <tr><td>课程名</td><td>学分</td><td>成绩</td></tr>
  <tr><td rowspan="2">高等数学</td><td>5</td><td>92</td></tr>
  <tr><td>5</td><td>85</td></tr>
</table>
</body></html>''';
  final HtmlTable? table = HtmlTableExtractor.largestTable(
    page,
    requiredHeaders: <String>['课程'],
  );
  check('选中数据表', table?.headers.first, '课程名');
  check('rowspan 展开后行数', table?.rowCount, 2);
  check('rowspan 填充值', table?.rows[1][0], '高等数学');
  check('合并后列不串位', table?.rows[1][2], '85');

  stdout.writeln('\n[6] 成绩解析（HTML 表格）');
  final List<ScoreRecord> fromHtml = UrpParser.parseScores(page);
  check('解析出 2 条', fromHtml.length, 2);
  check('课程名', fromHtml.first.courseName, '高等数学');
  check('学分', fromHtml.first.credit, '5');
  check('成绩', fromHtml.first.score, '92');
  final ScoreSummary summary = ScoreSummary.from(fromHtml);
  check('总学分', summary.totalCredits, 10.0);
  check('加权平均 88.5', (summary.weightedAverage ?? 0).toStringAsFixed(1), '88.5');

  stdout.writeln('\n[7] 成绩解析（AJAX JSON）');
  final Map<String, dynamic> payload = <String, dynamic>{
    'lnList': <dynamic>[
      <String, dynamic>{
        'cjbh': '2024-2025秋',
        'cjList': <dynamic>[
          <String, dynamic>{
            'id': <String, dynamic>{'courseNumber': 'MATH1001'},
            'courseName': '高等数学',
            'courseAttributeName': '必修',
            'credit': '5.0',
            'courseScore': '92',
            'gradeName': '4.2',
          },
          <String, dynamic>{
            'kcm': '大学物理',
            'kch': 'PHYS1001',
            'xf': '4',
            'cj': '78',
          },
        ],
      },
    ],
  };
  final List<ScoreRecord> fromJson = UrpParser.parseScoresJson(payload);
  check('解析出 2 条', fromJson.length, 2);
  check('字段映射', fromJson.first.courseName, '高等数学');
  check('课程号从 id 取', fromJson.first.courseCode, 'MATH1001');
  check('学期从 cjbh 取', fromJson.first.term, '2024-2025秋');
  check('变体字段 kcm/kch/xf/cj', fromJson[1].courseName, '大学物理');
  check('变体课程号', fromJson[1].courseCode, 'PHYS1001');
  check('空输入不抛异常', UrpParser.parseScoresJson(null).isEmpty, true);
  check('非 Map 输入不抛异常', UrpParser.parseScoresJson('abc').isEmpty, true);

  stdout.writeln('\n[8] 课表解析（对照真实 ajaxStudentSchedule 结构）');
  final Map<String, dynamic> tt = <String, dynamic>{
    'xkxx': <dynamic>[
      <String, dynamic>{
        '11711113_01': <String, dynamic>{
          'courseName': '思想道德与法治',
          'attendClassTeacher': '武雅君* ',
          'unit': 3,
          'coursePropertiesName': '必修',
          'courseCategoryName': '2公共必修课',
          'studyModeName': '正常',
          'selectCourseStatusName': '置入',
          'skzcs': '4-15周',
          'id': <String, dynamic>{
            'coureNumber': '11711113',
            'coureSequenceNumber': '01',
          },
          'timeAndPlaceList': <dynamic>[
            <String, dynamic>{
              'classDay': 2,
              'classSessions': 5,
              'continuingSession': 2,
              'campusName': '东区',
              'teachingBuildingName': '第二公共教学楼',
              'classroomName': 'A415',
              'classWeek': '000111111111111000000000',
              'weekDescription': '4-15周',
            },
          ],
        },
      },
    ],
    'allUnits': 26.75,
    'csz': '1',
    'jcsjbs': <dynamic>[
      <String, dynamic>{'jc': '1', 'kssj': '0820', 'jssj': '0905'},
    ],
  };
  final Timetable timetable = UrpParser.parseTimetableJson(tt);
  check('课程数', timetable.courses.length, 1);
  check('课程名', timetable.courses.first.name, '思想道德与法治');
  check('教师去掉星号', timetable.courses.first.teacher, '武雅君');
  check('学分（unit）', timetable.courses.first.credit, '3');
  check('课程号从 id.coureNumber 取', timetable.courses.first.code, '11711113');
  check('课序号', timetable.courses.first.classSequence, '01');
  check('课程属性', timetable.courses.first.attribute, '必修');
  check('周次描述', timetable.courses.first.weeks, '4-15周');
  check('上课段数', timetable.courses.first.timePlaces.length, 1);

  final CourseTimePlace place = timetable.courses.first.timePlaces.first;
  check('星期', place.classDay, 2);
  check('起始节次', place.startSession, 5);
  check('连堂节数', place.sessionCount, 2);
  check('地点拼接', place.placeLabel, '第二公共教学楼A415');
  check('第 4 周上课', place.isActiveInWeek(4), true);
  check('第 2 周不上课', place.isActiveInWeek(2), false);
  check('总学分（allUnits 是数字）', timetable.totalCredits, 26.75);
  check('节次时间格式化', timetable.sections.first.startLabel, '08:20');
  check('按星期取课', timetable.coursesOn(2).length, 1);
  check('空输入不抛异常', UrpParser.parseTimetableJson(null).isEmpty, true);
  check('非 Map 输入不抛异常', UrpParser.parseTimetableJson('x').isEmpty, true);

  stdout.writeln('\n[9] 从页面提取 AJAX 接口');
  check(
    '带随机段的成绩接口',
    UrpApi.extractCallbackUrl(
      'var url = "/student/integratedQuery/scoreQuery/8U5kzu4lLM/allPassingScores/callback";',
    ),
    '/student/integratedQuery/scoreQuery/8U5kzu4lLM/allPassingScores/callback',
  );
  check(
    '固定路径的课表接口',
    UrpApi.extractCallbackUrl(
      r'url = "/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback"; $.get(url)',
    ),
    '/student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback',
  );
  check(
    '整页跳转不算接口',
    UrpApi.extractCallbackUrl('url: "/student/courseSelect/courseSelect/index"'),
    null,
  );
  check('没有接口时返回 null', UrpApi.extractCallbackUrl('<div>hi</div>'), null);

  stdout.writeln('\n[10] 真实课表数据回归（读 dump 里的实际响应）');
  final File realDump = File(
    '../../dump/api_26_student_courseSelect_thisSemesterCurriculum_ajaxStudentSchedule_callback.json',
  );
  if (realDump.existsSync()) {
    final Object? realJson = jsonDecode(realDump.readAsStringSync());
    final Timetable real = UrpParser.parseTimetableJson(realJson);
    check('真实课表课程数', real.courses.length, 14);
    check('总学分', real.totalCredits, 26.75);
    check('每门课都有课程名', real.courses.every((CourseInfo c) => c.name.isNotEmpty), true);
    check('每门课都有学分', real.courses.every((CourseInfo c) => c.credit.isNotEmpty), true);
    check('至少一门课有上课时间', real.courses.any((CourseInfo c) => c.timePlaces.isNotEmpty), true);
    check('节次表非空', real.sections.isNotEmpty, true);

    final CourseInfo maths = real.courses.firstWhere(
      (CourseInfo c) => c.name.contains('高等数学'),
      orElse: () => real.courses.first,
    );
    check('高数 学分', maths.credit, '6');
    check('高数 属性', maths.attribute, '必修');

    final CourseInfo sample = real.courses.first;
    stdout.writeln('  样例：${sample.name} / ${sample.teacher} / ${sample.credit}学分 / ${sample.weeks}');
    if (sample.timePlaces.isNotEmpty) {
      final CourseTimePlace p = sample.timePlaces.first;
      stdout.writeln('        周${p.classDay} 第${p.startSession}节 连${p.sessionCount}节 ${p.placeLabel}');
    }
  } else {
    stdout.writeln('  SKIP  未找到真实 dump，跳过');
  }

  stdout.writeln('\n[11] 课表网格布局（基于真实数据）');
  if (realDump.existsSync()) {
    final Object? raw = jsonDecode(realDump.readAsStringSync());
    final Timetable real = UrpParser.parseTimetableJson(raw);

    final TimetableGrid week5 = TimetableGrid.build(real, week: 5);
    final TimetableGrid week20 = TimetableGrid.build(real, week: 20);

    bool has(TimetableGrid g, String name) =>
        g.entries.any((GridEntry e) => e.course.name == name);

    check('第 5 周有「思想道德与法治」（4-15周）', has(week5, '思想道德与法治'), true);
    check('第 20 周没有它', has(week20, '思想道德与法治'), false);
    check('第 5 周有「高等数学C(理三1)」（4-19周）', has(week5, '高等数学C(理三1)'), true);
    // 边界：高数上到第 19 周，第 20 周就该消失了
    check(
      '第 19 周边界仍含高数',
      has(TimetableGrid.build(real, week: 19), '高等数学C(理三1)'),
      true,
    );
    check('第 20 周不含高数', has(week20, '高等数学C(理三1)'), false);

    final GridEntry? tuesday5 = week5.cellAt(2, 5);
    check('周二第 5 节命中课程', tuesday5 != null, true);
    check('该格课程是思想道德', tuesday5?.course.name, '思想道德与法治');
    check('连堂覆盖到第 6 节', week5.cellAt(2, 6)?.course.name, '思想道德与法治');
    check('第 4 节不是它', week5.cellAt(2, 4)?.course.name == '思想道德与法治', false);

    check('网格高度覆盖到第 6 节以上', week5.maxSession >= 6, true);
    check('第 5 周排课数与课程数量级一致', week5.entries.length >= 10, true);
    check('周次筛选真的在过滤', week20.entries.length <= week5.entries.length, true);
    check('冲突检测不抛异常', TimetableGrid.conflicts(week5).length >= 0, true);

    stdout.writeln('  第 5 周排了 ${week5.entries.length} 段课，最高到第 ${week5.maxSession} 节');
  } else {
    stdout.writeln('  SKIP  未找到真实 dump');
  }

  stdout.writeln('\n[12] 学期条解析（当前第几周）');
  const String termHtml = '''
    <a data-toggle="dropdown" class="dropdown-toggle" href="#" onclick="SchoolCalendar()">
      <i class="ace-icon fa fa-calendar"></i><span class='span_bbzx'>

2026-2027 秋 第13周 星期三</span>
    </a>''';
  final TermInfo? term = UrpParser.parseTermInfo(termHtml);
  check('解析出了学期条', term != null, true);
  check('学年 2026-2027', term?.year, '2026-2027');
  check('学期是秋', term?.term, '秋');
  check('第 13 周', term?.week, 13);
  check('星期三', term?.weekday, 3);
  check('标签拼得出来', term?.label, '2026-2027 秋 第13周');
  check('没有学期条时返回 null',
      UrpParser.parseTermInfo('<div>nothing here</div>'), null);
  check('有 span 但没有周次也返回 null',
      UrpParser.parseTermInfo("<span class='span_bbzx'>2026-2027 秋</span>"), null);

  final File rootDump = File('../../dump/01_root.html');
  if (rootDump.existsSync()) {
    final TermInfo? real = UrpParser.parseTermInfo(rootDump.readAsStringSync());
    check('真实首页解析出周次', real?.week, 13);
    check('真实首页学期是秋', real?.term, '秋');
    check('真实首页是星期三', real?.weekday, 3);
  } else {
    stdout.writeln('  SKIP  未找到 dump/01_root.html');
  }

  stdout.writeln('\n[13] 成绩分组与加权平均');
  const List<ScoreRecord> sample = <ScoreRecord>[
    ScoreRecord(
      courseName: '高等数学',
      credit: '3',
      score: '92',
      term: '2025-2026-1',
      courseType: '必修',
    ),
    ScoreRecord(
      courseName: '大学英语',
      credit: '2',
      score: '80',
      term: '2025-2026-1',
    ),
    ScoreRecord(
      courseName: '体育',
      credit: '1',
      score: '优秀',
      term: '2025-2026-1',
    ),
    ScoreRecord(
      courseName: '物理实验',
      credit: '1.5',
      score: '58',
      term: '2024-2025-2',
    ),
  ];
  final List<TermScores> groups = ScoreStats.groupByTerm(sample);
  check('分成两个学期', groups.length, 2);
  check('保持服务端顺序', groups.first.term, '2025-2026-1');
  check('第一学期 3 门', groups.first.records.length, 3);
  check('总学分 7.5', ScoreStats.totalCredits(sample), 7.5);
  check('单学期学分 6', groups.first.credits, 6.0);
  // (92*3 + 80*2) / 5，体育是「优秀」不参与
  check(
    '单学期加权平均 87.2',
    (groups.first.average! - 87.2).abs() < 1e-9,
    true,
  );
  // (92*3 + 80*2 + 58*1.5) / 6.5
  check(
    '全部加权平均含不及格',
    (ScoreStats.weightedAverage(sample)! - 523 / 6.5).abs() < 1e-9,
    true,
  );
  check('及格 3 门', ScoreStats.passedCount(sample), 3);
  check('不及格 1 门', ScoreStats.failedCount(sample), 1);
  check('「优秀」算及格',
      const ScoreRecord(courseName: 'x', score: '优秀').isPassed, true);
  check('「合格」算及格',
      const ScoreRecord(courseName: 'x', score: '合格').isPassed, true);
  check(
    '空学期归到「未标注学期」',
    ScoreStats.groupByTerm(
      const <ScoreRecord>[ScoreRecord(courseName: 'x', score: '90')],
    ).first.term,
    ScoreStats.unknownTerm,
  );
  check('没有数字成绩时平均为 null',
      ScoreStats.weightedAverage(
        const <ScoreRecord>[ScoreRecord(courseName: 'x', score: '优秀')],
      ),
      null);
  check('学分缺失按权重 1 算',
      (ScoreStats.weightedAverage(
        const <ScoreRecord>[
          ScoreRecord(courseName: 'a', score: '90'),
          ScoreRecord(courseName: 'b', score: '80'),
        ],
      )! - 85.0).abs() < 1e-9, true);

  stdout.writeln('\n[14] 待办解析（学分确认 / 学业预警）');
  // 接口返回「没有」的方式很随意：203 / "" / "null" / "ok"，都得当空处理。
  check('203 就是没有待确认',
      UrpParser.hasCreditConfirmPending(<String, dynamic>{'status': '203', 'msg': 'null', 'data': ''}),
      false);
  check('data 是空串也算没有',
      UrpParser.hasCreditConfirmPending(<String, dynamic>{'status': '200', 'data': '  '}),
      false);
  check('data 是 "null" 也算没有',
      UrpParser.hasCreditConfirmPending(<String, dynamic>{'status': '200', 'data': 'null'}),
      false);
  check('有列表就是有待办',
      UrpParser.hasCreditConfirmPending(<String, dynamic>{
        'status': '200',
        'data': <Object>[<String, Object>{'x': 1}],
      }),
      true);
  check('不是 Map 一律当没有', UrpParser.hasCreditConfirmPending('oops'), false);

  check('"ok" 表示没有预警',
      UrpParser.parseWarnings(<String, dynamic>{'status': 200, 'msg': 'OK', 'data': 'ok'}),
      <String>[]);
  check('data 为 null 没有预警',
      UrpParser.parseWarnings(<String, dynamic>{'status': 200, 'data': null}),
      <String>[]);
  check('字符串预警原样返回',
      UrpParser.parseWarnings(<String, dynamic>{'status': 200, 'data': ' 学分不足 '}),
      <String>['学分不足']);
  check('取 content 字段',
      UrpParser.parseWarnings(<String, dynamic>{
        'status': 200,
        'data': <Object>[
          <String, Object>{'content': '必修课挂科 2 门'},
          <String, Object>{'msg': '学分预警'},
        ],
      }),
      <String>['必修课挂科 2 门', '学分预警']);
  check('取不到字段的项跳过',
      UrpParser.parseWarnings(<String, dynamic>{
        'status': 200,
        'data': <Object>[<String, Object>{'id': 1}],
      }),
      <String>[]);

  final File creditDump = File(
      '../../dump/api_40_student_courseSelect_creditCheck_queryAll.json');
  if (creditDump.existsSync()) {
    check(
      '真实学分确认响应：没有待办',
      UrpParser.hasCreditConfirmPending(
          jsonDecode(creditDump.readAsStringSync())),
      false,
    );
  } else {
    stdout.writeln('  SKIP  未找到学分确认 dump');
  }

  final File warnDump = File('../../dump/api_15_main_queryWarningDetailedInfo.json');
  if (warnDump.existsSync()) {
    check(
      '真实学业预警响应：空列表',
      UrpParser.parseWarnings(jsonDecode(warnDump.readAsStringSync())),
      <String>[],
    );
  } else {
    stdout.writeln('  SKIP  未找到学业预警 dump');
  }

  check('TodoItem 默认 kind 是 other',
      const TodoItem(title: 't').kind, TodoKind.other);
  check('TodoItem detail 默认空串', const TodoItem(title: 't').detail, '');
  check('TodoItem 能带上跳转路径',
      const TodoItem(title: 't', path: '/student/application/index').path,
      '/student/application/index');

  stdout.writeln('\n[15] 今日课程（首页卡片）');
  const String todayJson = '''
{"xkxx":[{"k":{"courseName":"高等数学","attendClassTeacher":"张三* ","unit":"4","skzcs":"3-16周",
"id":{"coureNumber":"M1","coureSequenceNumber":"01"},"timeAndPlaceList":[
 {"teachingBuildingName":"一教","classroomName":"A101","classDay":3,"classSessions":1,"continuingSession":2,"classWeek":"001111111111111100000000","weekDescription":"3-16周"},
 {"teachingBuildingName":"二教","classroomName":"B202","classDay":3,"classSessions":5,"continuingSession":2,"classWeek":"001111111111111100000000","weekDescription":"3-16周"}]}},
 {"k":{"courseName":"体育","attendClassTeacher":"李四","unit":"1","skzcs":"1-16周",
"id":{"coureNumber":"P1","coureSequenceNumber":"02"},"timeAndPlaceList":[
 {"teachingBuildingName":"体育馆","classroomName":"","classDay":2,"classSessions":3,"continuingSession":2,"classWeek":"111111111111111111111111","weekDescription":"1-16周"}]}}],
"allUnits":5,"jcsjbs":[{"jc":"1","kssj":"0820","jssj":"0905"},{"jc":"2","kssj":"0915","jssj":"1000"},
{"jc":5,"kssj":"1330","jssj":"1415"},{"jc":6,"kssj":"1425","jssj":"1510"}]}
''';
  final Timetable todayTable =
      UrpParser.parseTimetableJson(jsonDecode(todayJson));
  const TermInfo wed5 = TermInfo(
      year: '2026-2027', term: '秋', week: 5, weekday: 3);
  final TodaySchedule wed = buildTodaySchedule(todayTable, wed5);
  check('周三排了 2 节', wed.classes.length, 2);
  check('按起始节次排序', wed.classes.first.startSession, 1);
  check('作息时间拼成 08:20-10:00', wed.classes.first.timeRange, '08:20-10:00');
  check('教室带进来了', wed.classes.first.room.contains('A101'), true);
  check('教师去掉了主讲星号', wed.classes.first.teacher, '张三');
  check('节次标签是第1-2节', wed.classes.first.sessionLabel, '第1-2节');
  check('星期标签是「三」', wed.weekdayLabel, '三');
  check('周次一路带下来', wed.week, 5);
  check(
    '周五没课',
    buildTodaySchedule(
      todayTable,
      const TermInfo(year: '2026-2027', term: '秋', week: 5, weekday: 5),
    ).isEmpty,
    true,
  );
  check(
    '第 20 周周三没课（课只到 16 周）',
    buildTodaySchedule(
      todayTable,
      const TermInfo(year: '2026-2027', term: '秋', week: 20, weekday: 3),
    ).isEmpty,
    true,
  );
  check(
    '第 1 周周三没课（高数从第 3 周起）',
    buildTodaySchedule(
      todayTable,
      const TermInfo(year: '2026-2027', term: '秋', week: 1, weekday: 3),
    ).isEmpty,
    true,
  );
  check('周二只有体育一节',
      buildTodaySchedule(
        todayTable,
        const TermInfo(year: '2026-2027', term: '秋', week: 5, weekday: 2),
      ).classes.length,
      1);

  final File todayDump = File(
      '../../dump/api_26_student_courseSelect_thisSemesterCurriculum_ajaxStudentSchedule_callback.json');
  if (todayDump.existsSync()) {
    final Timetable real =
        UrpParser.parseTimetableJson(jsonDecode(todayDump.readAsStringSync()));
    final TimetableGrid realGrid = TimetableGrid.build(real, week: 13);
    final TodaySchedule realWed = buildTodaySchedule(real,
        const TermInfo(year: '2026-2027', term: '秋', week: 13, weekday: 3));
    check(
      '真实课表：今日课数与网格一致',
      realWed.classes.length,
      realGrid.entries.where((GridEntry e) => e.day == 3).length,
    );
    check('真实课表：今日每节都有作息时间',
        realWed.classes.every((TodayClass c) => c.timeRange.isNotEmpty), true);
    check('真实课表：今日按节次有序',
        <int>[for (final TodayClass c in realWed.classes) c.startSession]
            .every((int s) => s >= 1),
        true);
    stdout.writeln(
        '  第 13 周周三 ${realWed.classes.length} 节：'
        '${realWed.classes.map((TodayClass c) => '${c.timeRange} ${c.name}').join('、')}');
  } else {
    stdout.writeln('  SKIP  未找到真实课表 dump');
  }

  stdout.writeln('\n[16] HTML 编码嗅探（学习通页面 UTF-8 / GBK 混用）');
  const String cn = '无权限的操作！';
  check('UTF-8 正文按 UTF-8 解', decodeHtmlBytes(utf8.encode(cn)), cn);
  check('GBK 正文能自动嗅探出来', decodeHtmlBytes(gbk.encode(cn)), cn);
  check(
    '声明 gbk 但正文是 UTF-8（超星的真实坑）',
    decodeHtmlBytes(utf8.encode('无效的用户！'), declaredCharset: 'gbk'),
    '无效的用户！',
  );
  check('空字节返回空串', decodeHtmlBytes(const <int>[]), '');
  check('charsetOf 取 content-type', charsetOf('text/html; charset=GBK'), 'gbk');
  check('charsetOf 无声明返回 null', charsetOf(null), null);
  final File gbkProbe = File(
      '../../dump-cx/x53_work_846151_mooc1.chaoxing.com_mooc2_work_list_courseId_846151_ut_s.html');
  if (gbkProbe.existsSync()) {
    final String text = decodeHtmlBytes(gbkProbe.readAsBytesSync());
    check('真实页面解码后可读（含「无效的用户」）', text.contains('无效的用户'), true);
    check('真实页面解码后无替换符', text.contains('\uFFFD'), false);
  } else {
    stdout.writeln('  SKIP  未找到学习通页面样本');
  }

  stdout.writeln('\n[17] 学习通：课程列表 / 作业 URL / 作业解析');
  final File courseDump = File(
      '../../dump-cx/09_mooc1.chaoxing.com_mooc-ans_visit_stuendcourselist.html');
  if (courseDump.existsSync()) {
    final List<CxCourse> courses = parseCourseList(courseDump.readAsStringSync());
    check('真实课程列表：门数', courses.length, 2);
    check(
      '真实课程列表：课程名',
      courses.map((CxCourse c) => c.name).join(','),
      '有机化学实验,有机化学',
    );
    check(
      '真实课程列表：courseId/clazzId',
      '${courses.first.courseId}/${courses.first.clazzId}',
      '267530050/155823420',
    );
    check('真实课程列表：cpi 非空', courses.first.cpi.isNotEmpty, true);
  } else {
    stdout.writeln('  SKIP  未找到课程列表 dump');
  }

  final File coursePage = File(
      '../../dump-cx/27_mooc1.chaoxing.com_mooc-ans_visit_stucoursemiddle_courseid_267530050_clazzid_155823420_vc_.html');
  if (coursePage.existsSync()) {
    final CourseContext? ctx = parseCourseContext(coursePage.readAsStringSync());
    check('真实课程页：解析出隐藏域', ctx != null, true);
    check('真实课程页：cpi', ctx?.cpi, '562623583');
    check('真实课程页：enc（stuenc 用的那个）', ctx?.enc.length, 32);
    check('真实课程页：workEnc 非空', (ctx?.workEnc ?? '').length, 32);
    check('真实课程页：enc ≠ workEnc',
        ctx?.enc != ctx?.workEnc, true);
    check('真实课程页：t 非空', (ctx?.t ?? '').isNotEmpty, true);
    if (ctx != null) {
      final Uri workUrl = buildWorkListUrl(ctx, Uri.parse('https://x/work/list'));
      check('作业 URL 带 enc=workEnc',
          workUrl.queryParameters['enc'] == ctx.workEnc, true);
      check('作业 URL 带 stuenc=enc',
          workUrl.queryParameters['stuenc'] == ctx.enc, true);
      check('作业 URL 带 t', workUrl.queryParameters['t'] == ctx.t, true);
      check('作业 URL 带 classId',
          workUrl.queryParameters['classId'] == ctx.clazzId, true);
      final Uri noStu = buildWorkListUrl(ctx, Uri.parse('https://x/work/list'),
          useStuenc: false);
      check('不带 stuenc 时该参数消失',
          noStu.queryParameters.containsKey('stuenc'), false);
      check('不带 stuenc 时 enc 仍在',
          noStu.queryParameters['enc'] == ctx.workEnc, true);
    }
  } else {
    stdout.writeln('  SKIP  未找到课程页 dump');
  }

  const String syntheticWork = '''
<ul>
  <li><a href="/mooc2/work/view?workId=1">第一次作业</a><span>未交</span> 截止时间 2026-11-30 23:59</li>
  <li><a href="/mooc2/work/view?workId=2">第二次作业</a><span>已交</span></li>
  <li><a href="/mooc2/work/view?workId=3">第三次作业</a><span>已过期</span></li>
</ul>
''';
  final HomeworkList parsed = parseWorkList(syntheticWork, courseName: '有机化学');
  check('合成作业：条数', parsed.length, 3);
  check('合成作业：未交条数', parsed.pendingCount, 1);
  check('合成作业：标题', parsed.items.first.title, '第一次作业');
  check('合成作业：状态归一', parsed.items.first.status, HomeworkStatus.notSubmitted);
  check('合成作业：截止时间', parsed.items.first.deadline, '2026-11-30 23:59');
  check('合成作业：已交状态', parsed.items[1].status, HomeworkStatus.submitted);
  check('合成作业：过期状态', parsed.items[2].status, HomeworkStatus.expired);
  check('状态归一：未提交不算已交', parseHomeworkStatus('未提交'),
      HomeworkStatus.notSubmitted);
  check('状态归一：待批阅', parseHomeworkStatus('待批阅'), HomeworkStatus.grading);
  check('空页面返回空列表', parseWorkList('').isEmpty, true);

  final File denial = File(
      '../../dump-cx/x53_work_846151_mooc1.chaoxing.com_mooc2_work_list_courseId_846151_ut_s.html');
  if (denial.existsSync()) {
    final String page = decodeHtmlBytes(denial.readAsBytesSync());
    bool threw = false;
    String thrown = '';
    try {
      parseWorkList(page);
    } on CxDeniedException catch (e) {
      threw = true;
      thrown = e.message;
    }
    check('真实提示页抛 CxDeniedException', threw, true);
    check('提示文案是「无效的用户」', thrown, '无效的用户');
  } else {
    stdout.writeln('  SKIP  未找到提示页样本');
  }

  // 真实「作业列表」页：两门课当前都还没有作业，页面形状是 .task-list + 暂无作业。
  // 这里锁两件事：URL 公式确实能拿到列表页（不是提示页），且空页不会被解析出假条目。
  const List<String> realWorkPages = <String>[
    'x47_work_267530050_mooc1.chaoxing.com_mooc2_work_list_courseId_267530050_classId_155823420_cpi_562623583_ut_s.html',
    'x49_work_267529936_mooc1.chaoxing.com_mooc2_work_list_courseId_267529936_classId_155823114_cpi_562623583_ut_s.html',
  ];
  for (final String name in realWorkPages) {
    final File page = File('../../dump-cx/$name');
    if (!page.existsSync()) {
      stdout.writeln('  SKIP  未找到 $name');
      continue;
    }
    final String html = decodeHtmlBytes(page.readAsBytesSync());
    check('真实作业页：标题是作业列表', html.contains('<title>作业列表</title>'), true);
    check('真实作业页：解析出零条（当前无作业）',
        parseWorkList(html, courseName: '有机化学').items.length, 0);
  }

  // 单条作业也要能解析：早期实现要求至少 2 个 <li> 才分块，
  // 只有一条作业时会退回整页、把导航链接当作业。
  const String oneWorkPage = '''
<html><body><div class="main task-list">
  <div class="filter"><ul><li>全部</li><li>已完成</li><li>未完成</li></ul></div>
  <ul>
    <li>
      <a href="/mooc2/work/view?courseId=1&workId=99&enc=abc">
        <p class="overhidden">第三章 习题</p>
      </a>
      <div class="statusbg">未提交</div>
      <span class="fs12">截止时间 2026-12-01 23:59</span>
    </li>
  </ul>
</div></body></html>''';
  final HomeworkList oneWork = parseWorkList(oneWorkPage, courseName: '有机化学');
  check('单条作业：解析出 1 条', oneWork.length, 1);
  check('单条作业：标题取自 overhidden', oneWork.items.first.title, '第三章 习题');
  check('单条作业：状态取自 statusbg 角标', oneWork.items.first.statusText, '未提交');
  check('单条作业：状态归一', oneWork.items.first.status, HomeworkStatus.notSubmitted);
  check('单条作业：截止时间', oneWork.items.first.deadline, '2026-12-01 23:59');
  check('单条作业：链接带 workId', oneWork.items.first.url.contains('workId=99'), true);

  const String brandNewPage = '''
<html><body><div class="main task-list">
  <div class="null-data" style="font-size: 14px;">暂无作业</div>
</div></body></html>''';
  check('空态快路径：暂无作业解析为零条', parseWorkList(brandNewPage).isEmpty, true);

  final HomeworkList emptyCourse = const HomeworkList(courseName: '空课');
  final HomeworkList merged = HomeworkList.merge(<HomeworkList>[
    parsed,
    emptyCourse,
  ]);
  check('合并后条数不变', merged.length, 3);
  check('合并后待交排第一', merged.items.first.isPending, true);

  // [18] 座位预约的时间规则与地址校验
  stdout.writeln('\n[18] 座位预约规则');
  final DateTime morning = DateTime(2026, 11, 25, 10, 0);
  check('上午未到开放时间', seatOpenNow(morning), false);
  check('上午距开放 12 小时', untilSeatOpen(morning).inMinutes, 12 * 60);
  check(
    '上午文案',
    seatCountdownLabel(morning),
    '距 22:00 开放还有 12 小时 0 分',
  );

  final DateTime almost = DateTime(2026, 11, 25, 21, 59);
  check('21:59 还未开放', seatOpenNow(almost), false);
  check('21:59 距开放 1 分钟', untilSeatOpen(almost).inMinutes, 1);
  check('21:59 文案', seatCountdownLabel(almost), '距 22:00 开放还有 1 分');

  final DateTime sharp = DateTime(2026, 11, 25, 22, 0);
  check('22:00 已开放', seatOpenNow(sharp), true);
  check('22:00 距开放为 0', untilSeatOpen(sharp), Duration.zero);
  check(
    '22:00 文案',
    seatCountdownLabel(sharp),
    '今天 22:00 已开放，可约明天的座位',
  );

  final DateTime lateNight = DateTime(2026, 11, 25, 23, 59);
  check('23:59 仍在开放窗口内', seatOpenNow(lateNight), true);
  final DateTime nextMorning = DateTime(2026, 11, 26, 1, 0);
  check('次日 01:00 不是开放时刻', seatOpenNow(nextMorning), false);
  check(
    '次日 01:00 下一次开放是当天 22:00',
    nextSeatOpen(nextMorning),
    DateTime(2026, 11, 26, 22, 0),
  );
  check(
    '次日 01:00 距开放 21 小时',
    untilSeatOpen(nextMorning).inMinutes,
    21 * 60,
  );

  check(
    '地址：正常 https',
    normalizeSeatUrl('https://seat.mh.chaoxing.com/engine2/general/more?t=ABC123'),
    'https://seat.mh.chaoxing.com/engine2/general/more?t=ABC123',
  );
  check(
    '地址：缺协议自动补',
    normalizeSeatUrl('  tgu.mh.chaoxing.com/engine2/general/more?t=FF  '),
    'https://tgu.mh.chaoxing.com/engine2/general/more?t=FF',
  );
  check(
    '地址：去掉包裹引号',
    normalizeSeatUrl('"https://i.chaoxing.com/base"'),
    'https://i.chaoxing.com/base',
  );
  check('地址：拒绝非学习通域名', normalizeSeatUrl('https://evil.example.com/x'), null);
  check(
    '地址：拒绝后缀伪装',
    normalizeSeatUrl('https://evilchaoxing.com/x'),
    null,
  );
  check('地址：拒绝 javascript 伪协议', normalizeSeatUrl('javascript:alert(1)'), null);
  check('地址：拒绝空串', normalizeSeatUrl('   '), null);
  check(
    '地址：学校域名允许',
    normalizeSeatUrl('https://lib.tiangong.edu.cn/a'),
    'https://lib.tiangong.edu.cn/a',
  );

  // [19] 注入 WebView 时按什么域写 Cookie
  stdout.writeln('\n[19] 座位页 Cookie 注入的域');
  check(
    '域：mh 子域 + 逐级父域',
    cookieDomainsFor('xyz.mh.chaoxing.com'),
    <String>['xyz.mh.chaoxing.com', '.mh.chaoxing.com', '.chaoxing.com'],
  );
  check(
    '域：两级域名',
    cookieDomainsFor('i.chaoxing.com'),
    <String>['i.chaoxing.com', '.chaoxing.com'],
  );
  check(
    '域：学校域',
    cookieDomainsFor('LIB.Tiangong.edu.cn'),
    <String>['lib.tiangong.edu.cn', '.tiangong.edu.cn'],
  );
  check(
    '域：跳过公共后缀 edu.cn',
    cookieDomainsFor('x.y.edu.cn'),
    <String>['x.y.edu.cn', '.y.edu.cn'],
  );
  check('域：单标签主机不加父域', cookieDomainsFor('localhost'), <String>['localhost']);
  check('域：空主机返回空', cookieDomainsFor('  '), const <String>[]);
  check('域：从地址取主机', hostOfUrl('https://a.b.chaoxing.com/x?t=1'), 'a.b.chaoxing.com');
  check('域：地址非法时主机为空', hostOfUrl('not a url'), '');

  // [20] 解析器健壮性巡检：真实抓回来的页面什么样都有，任何一页都不该让解析器炸
  stdout.writeln('\n[20] 真实页面解析巡检');
  final List<File> pages = <File>[];
  for (final String dir in <String>['../../dump', '../../dump-cx']) {
    final Directory d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final FileSystemEntity e in d.listSync()) {
      if (e is File && (e.path.endsWith('.html') || e.path.endsWith('.json'))) {
        pages.add(e);
      }
    }
  }
  final List<String> parseFailures = <String>[];
  for (final File f in pages) {
    final String text = decodeHtmlBytes(f.readAsBytesSync());
    try {
      UrpParser.parseScores(text);
      UrpParser.parseExams(text);
      UrpParser.parseTermInfo(text);
      parseCourseList(text);
      parseCourseContext(text);
      try {
        parseWorkList(text);
      } on CxDeniedException {
        // 提示页本来就该抛，这是设计内的行为，不算失败。
      }
      final String trimmed = text.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final Object? json = jsonDecode(trimmed);
          UrpParser.parseScoresJson(json);
          UrpParser.parseTimetableJson(json);
          UrpParser.parseWarnings(json);
          UrpParser.hasCreditConfirmPending(json);
        } on FormatException {
          // 长得像 JSON 但不是，跳过。
        }
      }
    } catch (error) {
      final String name = f.path.split(Platform.pathSeparator).last;
      parseFailures.add('$name: $error');
    }
  }
  stdout.writeln('  扫描 ${pages.length} 个真实页面');
  for (final String line in parseFailures.take(5)) {
    stdout.writeln('    ! $line');
  }
  check('巡检：确实扫到了页面', pages.isNotEmpty, true);
  check('巡检：解析器零异常', parseFailures.length, 0);

  stdout.writeln('\n结果：$_passed 通过，$_failed 失败\n');
  if (_failed > 0) exit(1);
}
