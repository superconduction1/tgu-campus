import 'models.dart';

/// 一个学期的成绩分组。
class TermScores {
  const TermScores({required this.term, required this.records});

  final String term;
  final List<ScoreRecord> records;

  /// 本学期已修学分（只统计能解析成数字的）。
  double get credits =>
      records.fold(0.0, (double sum, ScoreRecord r) => sum + (r.numericCredit ?? 0));

  /// 本学期加权平均分；一门都算不出来时返回 null。
  double? get average => ScoreStats.weightedAverage(records);

  bool get isEmpty => records.isEmpty;
}

/// 成绩的纯计算部分。
///
/// 抽出来是为了能测：界面里算加权平均，算法错了没人会发现。
class ScoreStats {
  ScoreStats._();

  static const String unknownTerm = '未标注学期';

  /// 按学期分组，**保持服务端返回的顺序**。
  ///
  /// URP 通常按学期倒序返回（新的在前），这里不重新排序——
  /// 学校自己的顺序比我们猜的可靠。
  static List<TermScores> groupByTerm(List<ScoreRecord> records) {
    final Map<String, List<ScoreRecord>> buckets = <String, List<ScoreRecord>>{};
    for (final ScoreRecord record in records) {
      final String term =
          record.term.trim().isEmpty ? unknownTerm : record.term.trim();
      buckets.putIfAbsent(term, () => <ScoreRecord>[]).add(record);
    }
    return buckets.entries
        .map((MapEntry<String, List<ScoreRecord>> entry) =>
            TermScores(term: entry.key, records: entry.value))
        .toList();
  }

  /// 已修总学分。
  static double totalCredits(List<ScoreRecord> records) =>
      records.fold(0.0, (double sum, ScoreRecord r) => sum + (r.numericCredit ?? 0));

  /// 学分加权平均分。
  ///
  /// 成绩不是数字的（优秀/合格/通过）不参与计算；
  /// 学分缺失或为 0 的按权重 1 处理，总比直接丢掉这门课合理。
  static double? weightedAverage(List<ScoreRecord> records) {
    double sum = 0;
    double weight = 0;
    for (final ScoreRecord record in records) {
      final double? score = record.numericScore;
      if (score == null) continue;
      final double? credit = record.numericCredit;
      final double w = (credit == null || credit <= 0) ? 1 : credit;
      sum += score * w;
      weight += w;
    }
    if (weight <= 0) return null;
    return sum / weight;
  }

  static int passedCount(List<ScoreRecord> records) =>
      records.where((ScoreRecord r) => r.isPassed).length;

  static int failedCount(List<ScoreRecord> records) =>
      records.where((ScoreRecord r) => !r.isPassed).length;
}
