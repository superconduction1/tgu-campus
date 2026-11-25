import '../../core/html_table.dart';
import 'models.dart';

/// 把 URP 的 HTML 表格解析成结构化数据。
///
/// 设计原则：**只依赖列名，不依赖 DOM 路径**。
/// URP 改版通常改样式和布局，但「课程名称」「学分」「成绩」这些列名很少动，
/// 所以按表头找列比写死 `table > tbody > tr:nth-child(3)` 稳得多。
class UrpParser {
  UrpParser._();

  static const List<String> _nameKeys = <String>['课程名称', '课程名', '课程'];
  static const List<String> _creditKeys = <String>['学分'];
  static const List<String> _scoreKeys = <String>['成绩', '分数', '总评'];
  static const List<String> _gpaKeys = <String>['绩点'];
  static const List<String> _typeKeys = <String>['课程性质', '课程属性', '性质'];
  static const List<String> _codeKeys = <String>['课程代码', '课程号'];
  static const List<String> _termKeys = <String>['学期', '学年'];
  static const List<String> _examTypeKeys = <String>['考试性质', '考核方式', '考试类型'];

  static const List<String> _timeKeys = <String>['考试时间', '时间', '日期'];
  static const List<String> _placeKeys = <String>['考试地点', '地点', '考场'];
  static const List<String> _seatKeys = <String>['座位号', '座位'];
  static const List<String> _ticketKeys = <String>['准考证号', '准考证'];

  /// 解析成绩表。
  ///
  /// 找不到课程名称列就返回空列表——宁可空着，也不要吐出一堆错位数据。
  static List<ScoreRecord> parseScores(String html) {
    final HtmlTable? table = HtmlTableExtractor.largestTable(
      html,
      requiredHeaders: <String>['课程'],
    );
    if (table == null) return const <ScoreRecord>[];

    final int nameIndex = _find(table.headers, _nameKeys);
    if (nameIndex < 0) return const <ScoreRecord>[];

    final int creditIndex = _find(table.headers, _creditKeys);
    final int scoreIndex = _find(table.headers, _scoreKeys);
    final int gpaIndex = _find(table.headers, _gpaKeys);
    final int typeIndex = _find(table.headers, _typeKeys);
    final int codeIndex = _find(table.headers, _codeKeys);
    final int termIndex = _find(table.headers, _termKeys);
    final int examTypeIndex = _find(table.headers, _examTypeKeys);

    final List<ScoreRecord> result = <ScoreRecord>[];
    for (final List<String> row in table.rows) {
      final String name = _at(row, nameIndex);
      if (name.isEmpty) continue;
      result.add(
        ScoreRecord(
          courseName: name,
          courseCode: _at(row, codeIndex),
          courseType: _at(row, typeIndex),
          credit: _at(row, creditIndex),
          score: _at(row, scoreIndex),
          gpa: _at(row, gpaIndex),
          term: _at(row, termIndex),
          examType: _at(row, examTypeIndex),
        ),
      );
    }
    return result;
  }

  /// 解析考试安排表。
  static List<ExamRecord> parseExams(String html) {
    final HtmlTable? table = HtmlTableExtractor.largestTable(
      html,
      requiredHeaders: <String>['课程'],
    );
    if (table == null) return const <ExamRecord>[];

    final int nameIndex = _find(table.headers, _nameKeys);
    if (nameIndex < 0) return const <ExamRecord>[];

    final int timeIndex = _find(table.headers, _timeKeys);
    final int placeIndex = _find(table.headers, _placeKeys);
    final int seatIndex = _find(table.headers, _seatKeys);
    final int examTypeIndex = _find(table.headers, _examTypeKeys);
    final int ticketIndex = _find(table.headers, _ticketKeys);

    final List<ExamRecord> result = <ExamRecord>[];
    for (final List<String> row in table.rows) {
      final String name = _at(row, nameIndex);
      if (name.isEmpty) continue;
      result.add(
        ExamRecord(
          courseName: name,
          examTime: _at(row, timeIndex),
          location: _at(row, placeIndex),
          seatNo: _at(row, seatIndex),
          examType: _at(row, examTypeIndex),
          ticketNo: _at(row, ticketIndex),
        ),
      );
    }
    return result;
  }

  // ---------- JSON 版 ----------
  //
  // URP 的成绩页表格只是空壳，真实数据由页面里的 AJAX 回调返回 JSON：
  //   GET /student/integratedQuery/scoreQuery/{随机段}/allPassingScores/callback
  // 字段名从页面拼接 HTML 的 JS 里读出来，这里做了同义词容错。

  /// 解析成绩接口返回的 JSON。
  ///
  /// 期望结构（实际字段名可能有出入，已做容错）：
  /// ```json
  /// {"lnList":[{"cjbh":"2024-2025秋","cjlx":"必修","yxxf":"30",
  ///   "cjList":[{"id":{"courseNumber":"MATH1001"},"courseName":"高等数学",
  ///              "courseAttributeName":"必修","credit":"5",
  ///              "courseScore":"92","gradeName":"4.2"}]}]}
  /// ```
  static List<ScoreRecord> parseScoresJson(Object? json) {
    final List<Object?> terms = _asList(
      _get(json, <String>['lnList', 'data', 'list', 'result']),
    );
    final List<ScoreRecord> result = <ScoreRecord>[];

    for (final Object? term in terms) {
      if (term is! Map) continue;
      final String termName =
          _pick(term, <String>['cjbh', 'term', 'xnxq', 'xq', 'name']);

      final List<Object?> items = _asList(
        _get(term, <String>['cjList', 'courses', 'list', 'rows', 'data']),
      );

      for (final Object? item in items) {
        if (item is! Map) continue;
        final String name =
            _pick(item, <String>['courseName', 'kcm', 'course_name']);
        if (name.isEmpty) continue;

        String code = _pick(item, <String>['courseNumber', 'kch']);
        if (code.isEmpty) {
          final Object? id = item['id'];
          if (id is Map) code = _pick(id, <String>['courseNumber', 'kch']);
        }

        result.add(
          ScoreRecord(
            courseName: name,
            courseCode: code,
            courseType: _pick(
              item,
              <String>['courseAttributeName', 'kcsx', 'courseType', 'kclb'],
            ),
            credit: _pick(item, <String>['credit', 'xf']),
            score: _pick(item, <String>['courseScore', 'cj', 'score']),
            gpa: _pick(item, <String>['gradeName', 'jd', 'gpa']),
            term: termName,
          ),
        );
      }
    }
    return result;
  }

  /// 解析课表接口 `ajaxStudentSchedule/callback` 返回的 JSON。
  ///
  /// 结构（从页面 JS 反推，`xkxx` 的形状可能随学期变化）：
  /// ```json
  /// {"xkxx":[{"<课程key>":{"kch":"MATH1001","kcm":"高等数学","js":"张三",
  ///                        "xf":"5","kxh":"01","kcsx":"必修"}}],
  ///  "dateList":[...], "allUnits":[...], "csz":"1", "rwbgLists":[...]}
  /// ```
  ///
  /// 因为 `xkxx` 到底是「数组套映射」还是「映射套数组」没有 100% 把握，
  /// 这里用递归收集：凡是带 `kcm` / `kch` / `courseName` 的 Map 就当作一门课。
  static Timetable parseTimetableJson(Object? json) {
    if (json is! Map) {
      return const Timetable(courses: <CourseInfo>[]);
    }

    final List<Map<dynamic, dynamic>> found = <Map<dynamic, dynamic>>[];
    void collect(Object? node) {
      if (node is Map) {
        if (node.containsKey('kcm') ||
            node.containsKey('kch') ||
            node.containsKey('courseName')) {
          found.add(node);
          return;
        }
        for (final Object? value in node.values) {
          collect(value);
        }
      } else if (node is List) {
        for (final Object? value in node) {
          collect(value);
        }
      }
    }

    collect(json['xkxx']);

    final List<CourseInfo> courses = <CourseInfo>[];
    final Set<String> seen = <String>{};
    for (final Map<dynamic, dynamic> item in found) {
      final String name = _pick(item, <String>['courseName', 'kcm']);
      final Object? id = item['id'];
      String code = id is Map
          ? _pick(id, <String>['coureNumber', 'courseNumber', 'kch'])
          : '';
      String sequence = id is Map
          ? _pick(id, <String>['coureSequenceNumber', 'courseSequenceNumber'])
          : '';
      if (code.isEmpty) code = _pick(item, <String>['kch', 'coureNumber']);
      if (sequence.isEmpty) sequence = _pick(item, <String>['kxh']);
      if (name.isEmpty && code.isEmpty) continue;
      if (!seen.add('$code#$sequence')) continue;

      courses.add(
        CourseInfo(
          code: code,
          name: name,
          classSequence: sequence,
          // 实测值形如「武雅君* 」「赵健* 刘丽妍」，星号是主讲标记
          teacher: _pick(
            item,
            <String>['attendClassTeacher', 'js', 'teacherName'],
          ).replaceAll('*', '').trim(),
          credit: _label(_get(item, <String>['unit', 'xf', 'credit'])),
          attribute: _pick(item, <String>['coursePropertiesName', 'kcsx']),
          category: _pick(item, <String>['courseCategoryName', 'kclb']),
          studyMode: _pick(item, <String>['studyModeName', 'xdfs']),
          selectState: _pick(item, <String>['selectCourseStatusName', 'xkzt']),
          weeks: _pick(item, <String>['skzcs']),
          timePlaces: _timePlaces(item['timeAndPlaceList']),
        ),
      );
    }

    return Timetable(
      courses: courses,
      totalCredits: _num(json['allUnits']),
      sections: _sections(json['jcsjbs']),
      raw: json.map(
        (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
      ),
    );
  }

  static List<CourseTimePlace> _timePlaces(Object? value) {
    final List<CourseTimePlace> out = <CourseTimePlace>[];
    for (final Object? item in _asList(value)) {
      if (item is! Map) continue;
      final int count = _int(item['continuingSession']);
      out.add(
        CourseTimePlace(
          classDay: _int(item['classDay']),
          startSession: _int(item['classSessions']),
          sessionCount: count <= 0 ? 1 : count,
          campus: _pick(item, <String>['campusName']),
          building: _pick(item, <String>['teachingBuildingName']),
          room: _pick(item, <String>['classroomName']),
          weekPattern: _pick(item, <String>['classWeek']),
          weekDescription: _pick(item, <String>['weekDescription']),
        ),
      );
    }
    return out;
  }

  static List<SectionTime> _sections(Object? value) {
    final List<SectionTime> out = <SectionTime>[];
    for (final Object? item in _asList(value)) {
      if (item is! Map) continue;
      out.add(
        SectionTime(
          index: _int(item['jc']),
          start: _pick(item, <String>['kssj']),
          end: _pick(item, <String>['jssj']),
        ),
      );
    }
    return out;
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static Object? _get(Object? map, List<String> keys) {
    if (map is! Map) return null;
    for (final String key in keys) {
      if (map.containsKey(key)) return map[key];
    }
    return null;
  }

  static List<Object?> _asList(Object? value) =>
      value is List ? value : const <Object?>[];

  static String _pick(Object? map, List<String> keys) {
    final Object? value = _get(map, keys);
    if (value == null) return '';
    return value.toString().trim();
  }

  /// 数字转文本：整数不带 `.0`。
  ///
  /// 课表接口里 `unit` 是数字（6），直接 `toString()` 会得到 `6.0`，
  /// 显示成「6.0 学分」很别扭。
  static String _label(Object? value) {
    if (value == null) return '';
    if (value is num) {
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    return value.toString().trim();
  }

  /// 在一组表头里按关键词找列号；找不到返回 -1。
  static int _find(List<String> headers, List<String> keys) {
    for (final String key in keys) {
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].trim() == key) return i;
      }
    }
    for (final String key in keys) {
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].contains(key)) return i;
      }
    }
    return -1;
  }

  static String _at(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  /// 学分确认查询有没有待办。
  ///
  /// 实测没有待确认项时是 `{"status":"203","msg":"null","data":""}`；
  /// 所以 `203` 是「查无数据」，不是错误。
  static bool hasCreditConfirmPending(Object? json) {
    if (json is! Map) return false;
    final Object? status = json['status'];
    final String code = status == null ? '' : status.toString();
    if (code == '203') return false;
    final Object? data = json['data'];
    if (data == null) return false;
    if (data is String) return data.trim().isNotEmpty && data.trim() != 'null';
    if (data is List) return data.isNotEmpty;
    if (data is Map) return data.isNotEmpty;
    return false;
  }

  /// 学业预警列表。
  ///
  /// 实测无预警时是 `{"status":200,"msg":"OK","data":"ok"}`，
  /// `data` 为 `"ok"` / `"null"` / 空串都表示没有预警。
  static List<String> parseWarnings(Object? json) {
    if (json is! Map) return const <String>[];
    final Object? data = json['data'];
    if (data == null) return const <String>[];
    if (data is String) {
      final String text = data.trim();
      if (text.isEmpty || text == 'ok' || text == 'null' || text == 'OK') {
        return const <String>[];
      }
      return <String>[text];
    }
    if (data is List) {
      return data
          .map(_warningText)
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    if (data is Map) {
      final String text = _warningText(data);
      return text.isEmpty ? const <String>[] : <String>[text];
    }
    return const <String>[];
  }

  static String _warningText(Object? item) {
    if (item is String) return item.trim();
    if (item is! Map) return item?.toString().trim() ?? '';
    for (final String key in <String>[
      'content',
      'msg',
      'message',
      'warningContent',
      'title',
      'name',
      'remark',
    ]) {
      final Object? value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  /// 页面顶部那条：`2026-2027 秋 第13周 星期三`。
  ///
  /// 选择器是 `<span class="span_bbzx">`，实测每个登录后页面都有。
  /// 有了它就不用为了「现在第几周」专门去抓校历页。
  static final RegExp _termSpan = RegExp(
    r'''<span[^>]*class=["'][^"']*bbzx[^"']*["'][^>]*>(.*?)</span>''',
    dotAll: true,
  );

  static TermInfo? parseTermInfo(String html) {
    final RegExpMatch? span = _termSpan.firstMatch(html);
    if (span == null) return null;

    final String text = span
        .group(1)!
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;

    final RegExpMatch? weekMatch = RegExp(r'第\s*(\d+)\s*周').firstMatch(text);
    if (weekMatch == null) return null;

    final RegExpMatch? yearMatch =
        RegExp(r'(\d{4})\s*[-—]\s*(\d{4})').firstMatch(text);

    String term = '';
    if (yearMatch != null) {
      final RegExpMatch? t = RegExp(r'^\s*(?:学年)?\s*([春秋夏])')
          .firstMatch(text.substring(yearMatch.end));
      if (t != null) term = t.group(1)!;
    }

    int weekday = 0;
    final RegExpMatch? wd =
        RegExp(r'星期\s*([一二三四五六日天])').firstMatch(text);
    if (wd != null) {
      final String ch = wd.group(1) == '天' ? '日' : wd.group(1)!;
      weekday = TermInfo.weekdayNames.indexOf(ch) + 1;
    }

    return TermInfo(
      year: yearMatch == null
          ? ''
          : '${yearMatch.group(1)}-${yearMatch.group(2)}',
      term: term,
      week: int.parse(weekMatch.group(1)!),
      weekday: weekday,
      raw: text,
    );
  }
}
