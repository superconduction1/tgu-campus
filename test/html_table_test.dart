import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/core/html_table.dart';

void main() {
  group('基础表格', () {
    const String html = '''
<table>
  <tr><td>学号</td><td>姓名</td><td>班级</td></tr>
  <tr><td>2023001</td><td>张三</td><td>软件2301</td></tr>
  <tr><td>2023002</td><td>李四</td><td>软件2301</td></tr>
</table>''';

    test('表头与行数', () {
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.headers, <String>['学号', '姓名', '班级']);
      expect(table.rowCount, 2);
    });

    test('按表头取值', () {
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.value(0, '姓名'), '张三');
      expect(table.value(1, '班级'), '软件2301');
      expect(table.value(0, '不存在的列'), '');
    });

    test('rowAsMap', () {
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.rowAsMap(1), <String, String>{
        '学号': '2023002',
        '姓名': '李四',
        '班级': '软件2301',
      });
    });
  });

  group('合并单元格', () {
    test('rowspan 向下填充，后续列的列号不串位', () {
      const String html = '''
<table>
  <tr><td>课程</td><td>学分</td><td>成绩</td></tr>
  <tr><td rowspan="2">高等数学</td><td>5</td><td>90</td></tr>
  <tr><td>5</td><td>85</td></tr>
</table>''';
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.rowCount, 2);
      expect(table.rows[1], <String>['高等数学', '5', '85']);
    });

    test('colspan 横向展开', () {
      const String html = '''
<table>
  <tr><td>项目</td><td colspan="2">分数</td></tr>
  <tr><td>数学</td><td>90</td><td>85</td></tr>
</table>''';
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.headers, <String>['项目', '分数', '分数']);
      expect(table.rows[0], <String>['数学', '90', '85']);
    });

    test('异常 colspan 被截断而不是爆内存', () {
      const String html = '<table><tr><td colspan="99999">x</td></tr></table>';
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.columnCount, lessThanOrEqualTo(100));
    });
  });

  group('嵌套表格', () {
    const String html = '''
<table id="outer">
  <tr><td>外层表头</td></tr>
  <tr><td>第一行</td></tr>
  <tr><td>第二行</td></tr>
  <tr><td>第三行</td></tr>
</table>
<table id="inner">
  <tr><td>内层表头</td></tr>
  <tr><td>内层一行</td></tr>
</table>''';

    test('按内容行数降序，外层表在前', () {
      final List<HtmlTable> tables = HtmlTableExtractor.extract(html);
      expect(tables, hasLength(2));
      expect(tables.first.meaningfulRowCount, 3);
    });

    test('largestTable 优先匹配必需表头', () {
      final HtmlTable? table = HtmlTableExtractor.largestTable(
        html,
        requiredHeaders: <String>['内层'],
      );
      expect(table?.headers, <String>['内层表头']);
    });

    test('requiredHeaders 不匹配时退回最大表', () {
      final HtmlTable? table = HtmlTableExtractor.largestTable(
        html,
        requiredHeaders: <String>['根本没有'],
      );
      expect(table?.headers, <String>['外层表头']);
    });
  });

  group('脏数据', () {
    test('全空白与 &nbsp; 被规整', () {
      const String html =
          '<table><tr><td> 成绩&nbsp;</td><td>\u3000</td></tr>'
          '<tr><td>  90  </td><td></td></tr></table>';
      final HtmlTable table = HtmlTableExtractor.extract(html).first;
      expect(table.headers.first, '成绩');
      expect(table.rows.first.first, '90');
    });

    test('没有表格返回空列表', () {
      expect(HtmlTableExtractor.extract('<html><body>hi</body></html>'), isEmpty);
      expect(HtmlTableExtractor.largestTable('<div>无表</div>'), isNull);
    });

    test('空表格被过滤', () {
      const String html = '<table><tr><td></td></tr></table>';
      expect(HtmlTableExtractor.extract(html), isEmpty);
    });
  });
}
