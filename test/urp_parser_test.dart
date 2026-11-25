import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/features/urp/models.dart';
import 'package:tgu_campus/features/urp/urp_parser.dart';

/// 造一个 URP 风格的页面：外面套一层布局表格，里面才是数据表。
/// 这样能同时验证「选对表」和「解析对列」。
String scorePage(String innerTable) => '''
<html><body>
<table class="layout"><tr><td>导航</td><td>欢迎你</td></tr></table>
$innerTable
<table class="footer"><tr><td>版权所有</td></tr></table>
</body></html>''';

void main() {
  group('成绩解析', () {
    final String html = scorePage('''
<table class="data">
  <tr>
    <td>序号</td><td>课程代码</td><td>课程名称</td><td>课程性质</td>
    <td>学分</td><td>成绩</td><td>绩点</td>
  </tr>
  <tr>
    <td>1</td><td>MATH1001</td><td>高等数学</td><td>必修</td>
    <td>5.0</td><td>92</td><td>4.2</td>
  </tr>
  <tr>
    <td>2</td><td>CS2001</td><td>数据结构</td><td>必修</td>
    <td>4.0</td><td>85</td><td>3.5</td>
  </tr>
  <tr>
    <td>3</td><td>PE1001</td><td>体育</td><td>选修</td>
    <td>1.0</td><td>优秀</td><td>4.0</td>
  </tr>
</table>''');

    test('行数正确、跳过布局表格', () {
      final List<ScoreRecord> records = UrpParser.parseScores(html);
      expect(records, hasLength(3));
    });

    test('各列取值正确', () {
      final List<ScoreRecord> records = UrpParser.parseScores(html);
      expect(records[0].courseName, '高等数学');
      expect(records[0].courseCode, 'MATH1001');
      expect(records[0].courseType, '必修');
      expect(records[0].credit, '5.0');
      expect(records[0].score, '92');
      expect(records[0].gpa, '4.2');
    });

    test('非数字成绩不算及格判断错误', () {
      final List<ScoreRecord> records = UrpParser.parseScores(html);
      expect(records[2].numericScore, isNull);
      expect(records[2].isPassed, isTrue);
      expect(records[1].isPassed, isTrue);
    });

    test('不及格识别', () {
      const String failing = '<table><tr><td>课程名称</td><td>学分</td><td>成绩</td></tr>'
          '<tr><td>线性代数</td><td>3</td><td>52</td></tr></table>';
      expect(UrpParser.parseScores(failing).single.isPassed, isFalse);
    });

    test('加权平均与总学分', () {
      final ScoreSummary summary =
          ScoreSummary.from(UrpParser.parseScores(html));
      // (5*92 + 4*85) / 9 = 820/9 ≈ 91.11；「优秀」不参与计算
      expect(summary.totalCredits, 9.0);
      expect(summary.weightedAverage, closeTo(91.11, 0.01));
    });

    test('没有课程名称列时返回空，而不是吐错位数据', () {
      const String noName = '<table><tr><td>序号</td><td>成绩</td></tr>'
          '<tr><td>1</td><td>90</td></tr></table>';
      expect(UrpParser.parseScores(noName), isEmpty);
    });

    test('空行被跳过', () {
      const String withBlank = '<table>'
          '<tr><td>课程名称</td><td>学分</td><td>成绩</td></tr>'
          '<tr><td></td><td></td><td></td></tr>'
          '<tr><td>英语</td><td>2</td><td>88</td></tr>'
          '</table>';
      expect(UrpParser.parseScores(withBlank), hasLength(1));
    });
  });

  group('考试解析', () {
    const String html = '''
<table>
  <tr><td>课程名称</td><td>考试时间</td><td>考试地点</td><td>座位号</td></tr>
  <tr><td>高等数学</td><td>2026-01-12 09:00-11:00</td><td>A301</td><td>18</td></tr>
</table>''';

    test('各列取值正确', () {
      final List<ExamRecord> exams = UrpParser.parseExams(html);
      expect(exams, hasLength(1));
      expect(exams[0].courseName, '高等数学');
      expect(exams[0].examTime, '2026-01-12 09:00-11:00');
      expect(exams[0].location, 'A301');
      expect(exams[0].seatNo, '18');
    });

    test('列名变体也能匹配（考场 / 时间）', () {
      const String variant = '<table>'
          '<tr><td>课程</td><td>时间</td><td>考场</td></tr>'
          '<tr><td>大学物理</td><td>2026-01-15</td><td>B201</td></tr>'
          '</table>';
      final List<ExamRecord> exams = UrpParser.parseExams(variant);
      expect(exams.single.location, 'B201');
      expect(exams.single.examTime, '2026-01-15');
    });

    test('空表格返回空列表', () {
      expect(UrpParser.parseExams('<div>暂无考试安排</div>'), isEmpty);
    });
  });

  group('成绩 JSON 解析', () {
    Map<String, dynamic> payload() => <String, dynamic>{
          'lnList': <dynamic>[
            <String, dynamic>{
              'cjbh': '2024-2025秋',
              'cjlx': '主修',
              'yxxf': '9.0',
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
                  'id': <String, dynamic>{'courseNumber': 'CS2001'},
                  'courseName': '数据结构',
                  'courseAttributeName': '必修',
                  'credit': '4.0',
                  'courseScore': '85',
                  'gradeName': '3.5',
                },
              ],
            },
          ],
        };

    test('解析出全部课程', () {
      expect(UrpParser.parseScoresJson(payload()), hasLength(2));
    });

    test('字段映射正确', () {
      final List<ScoreRecord> scores = UrpParser.parseScoresJson(payload());
      expect(scores.first.courseName, '高等数学');
      expect(scores.first.courseCode, 'MATH1001');
      expect(scores.first.courseType, '必修');
      expect(scores.first.credit, '5.0');
      expect(scores.first.score, '92');
      expect(scores.first.gpa, '4.2');
    });

    test('学期从 cjbh 带过来', () {
      final List<ScoreRecord> scores = UrpParser.parseScoresJson(payload());
      expect(scores.every((ScoreRecord s) => s.term == '2024-2025秋'), isTrue);
    });

    test('课程号在 id 里也能取到', () {
      final List<ScoreRecord> scores = UrpParser.parseScoresJson(payload());
      expect(scores[1].courseCode, 'CS2001');
    });

    test('加权平均可算', () {
      final ScoreSummary summary =
          ScoreSummary.from(UrpParser.parseScoresJson(payload()));
      expect(summary.totalCredits, 9.0);
      expect(summary.weightedAverage, closeTo(88.89, 0.01));
    });

    test('字段名变体（kcm / kch / xf / cj）', () {
      final Map<String, dynamic> variant = <String, dynamic>{
        'lnList': <dynamic>[
          <String, dynamic>{
            'cjbh': '2025-2026春',
            'cjList': <dynamic>[
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
      final List<ScoreRecord> scores = UrpParser.parseScoresJson(variant);
      expect(scores.single.courseName, '大学物理');
      expect(scores.single.courseCode, 'PHYS1001');
      expect(scores.single.credit, '4');
      expect(scores.single.score, '78');
    });

    test('没有课程名的条目被跳过', () {
      final Map<String, dynamic> junk = <String, dynamic>{
        'lnList': <dynamic>[
          <String, dynamic>{
            'cjList': <dynamic>[
              <String, dynamic>{'credit': '3'},
            ],
          },
        ],
      };
      expect(UrpParser.parseScoresJson(junk), isEmpty);
    });

    test('空 / 非预期输入不抛异常', () {
      expect(UrpParser.parseScoresJson(null), isEmpty);
      expect(UrpParser.parseScoresJson(<String, dynamic>{}), isEmpty);
      expect(UrpParser.parseScoresJson('不是 JSON'), isEmpty);
      expect(UrpParser.parseScoresJson(<dynamic>[]), isEmpty);
    });
  });
}
