import 'package:flutter/material.dart';

import 'cx_page.dart';
import 'models.dart';

/// 作业详情：用内置 WebView 打开学习通的作业页。
///
/// 题目、要求、已交/未交、批阅结果都在那个页面里。
/// 真正提交作业仍然是用户在学习通里点，本应用不代做也不代交。
class HomeworkDetailPage extends StatelessWidget {
  const HomeworkDetailPage({super.key, required this.item});

  final HomeworkItem item;

  @override
  Widget build(BuildContext context) {
    final String title = item.title.isEmpty ? '作业' : item.title;
    if (item.url.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Text('这条作业没有可打开的链接')),
      );
    }
    return CxWebViewPage(title: title, url: item.url);
  }
}
