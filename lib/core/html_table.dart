import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 一张被展平成二维网格的 HTML 表格。
///
/// 之所以要专门做这一层：URP 的成绩、考试、课表、待办全都是服务端渲染的
/// `<table>`，而且课表那类还大量使用 `rowspan` / `colspan`。直接按 `<tr>` 读
/// 会把合并单元格算错位，所以先把它们展开成规整网格。
class HtmlTable {
  HtmlTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  int get rowCount => rows.length;

  int get columnCount => headers.length;

  bool get isEmpty => rows.isEmpty;

  /// 按表头名取值，找不到就返回空串。
  String value(int rowIndex, String header) {
    final int index = headers.indexOf(header);
    if (index < 0 || rowIndex >= rows.length) return '';
    final List<String> row = rows[rowIndex];
    return index < row.length ? row[index] : '';
  }

  Map<String, String> rowAsMap(int rowIndex) {
    final Map<String, String> map = <String, String>{};
    for (int i = 0; i < headers.length; i++) {
      final String key = headers[i];
      if (key.isEmpty) continue;
      final List<String> row = rows[rowIndex];
      map[key] = i < row.length ? row[i] : '';
    }
    return map;
  }

  /// 去掉全空行后的行数，用来判断这张表是不是「真表格」。
  int get meaningfulRowCount => rows
      .where((List<String> row) => row.any((String c) => c.trim().isNotEmpty))
      .length;

  @override
  String toString() => 'HtmlTable(${headers.length}x$rowCount)';
}

class HtmlTableExtractor {
  HtmlTableExtractor._();

  /// 抽出文档里所有表格，按「有内容的行数」从多到少排序。
  ///
  /// 嵌套表格会被单独列出——URP 页面经常表格套表格，
  /// 调用方通常要的是最大的那张，见 [largestTable]。
  static List<HtmlTable> extract(String html) {
    final Document document = html_parser.parse(html);
    final List<HtmlTable> tables = <HtmlTable>[];
    for (final Element element in document.querySelectorAll('table')) {
      final HtmlTable? table = _fromElement(element);
      if (table != null && table.meaningfulRowCount > 0) tables.add(table);
    }
    tables.sort((HtmlTable a, HtmlTable b) =>
        b.meaningfulRowCount.compareTo(a.meaningfulRowCount));
    return tables;
  }

  /// 取最有可能是数据表的那一张。
  ///
  /// [requiredHeaders] 用来做筛选：表头包含全部关键词的表格优先。
  static HtmlTable? largestTable(
    String html, {
    List<String> requiredHeaders = const <String>[],
  }) {
    final List<HtmlTable> tables = extract(html);
    if (tables.isEmpty) return null;
    if (requiredHeaders.isEmpty) return tables.first;
    for (final HtmlTable table in tables) {
      final bool hit = requiredHeaders
          .every((String h) => table.headers.any((String x) => x.contains(h)));
      if (hit) return table;
    }
    return tables.first;
  }

  static HtmlTable? _fromElement(Element table) {
    final List<Element> trs = table
        .querySelectorAll('tr')
        // 只要直属这张表的行，嵌套表格的行交给它自己。
        .where((Element tr) => _nearestTable(tr) == table)
        .toList();
    if (trs.isEmpty) return null;

    final List<List<String>> grid = <List<String>>[];
    final Map<int, Map<int, String>> pending = <int, Map<int, String>>{};

    for (int r = 0; r < trs.length; r++) {
      final List<Element> cells = trs[r]
          .children
          .where((Element e) => e.localName == 'td' || e.localName == 'th')
          .toList();
      final List<String> row = <String>[];
      int column = 0;

      // 先把上方 rowspan 遗留下来、占住本行的格子填进去
      final Map<int, String>? carried = pending[r];
      if (carried != null) {
        for (final MapEntry<int, String> entry in carried.entries) {
          while (row.length <= entry.key) {
            row.add('');
          }
          row[entry.key] = entry.value;
        }
      }

      for (final Element cell in cells) {
        while (column < row.length && row[column].isNotEmpty) {
          column++;
        }
        final String text = _clean(cell.text);
        final int colspan = _span(cell, 'colspan');
        final int rowspan = _span(cell, 'rowspan');

        for (int dc = 0; dc < colspan; dc++) {
          final int target = column + dc;
          while (row.length <= target) {
            row.add('');
          }
          row[target] = text;
        }

        if (rowspan > 1) {
          for (int dr = 1; dr < rowspan; dr++) {
            final int targetRow = r + dr;
            final Map<int, String> slot =
                pending.putIfAbsent(targetRow, () => <int, String>{});
            for (int dc = 0; dc < colspan; dc++) {
              slot[column + dc] = text;
            }
          }
        }

        column += colspan;
      }

      grid.add(row);
    }

    if (grid.isEmpty) return null;

    // 首行当表头；URP 常见做法是表头也用 <td>，所以不能只认 <th>。
    final List<String> headers = grid.first;
    final List<List<String>> rows = grid.skip(1).toList();
    return HtmlTable(headers: headers, rows: rows);
  }

  static Element? _nearestTable(Element tr) {
    Element? node = tr.parent;
    while (node != null) {
      if (node.localName == 'table') return node;
      node = node.parent;
    }
    return null;
  }

  static int _span(Element cell, String name) {
    final String? raw = cell.attributes[name];
    if (raw == null) return 1;
    final int? value = int.tryParse(raw.trim());
    if (value == null || value < 1) return 1;
    // 个别页面会写成 999 表示「一直到结尾」，截断防止爆内存。
    return value > 100 ? 100 : value;
  }

  static String _clean(String input) => input
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\s\u3000]+'), ' ')
      .trim();
}
