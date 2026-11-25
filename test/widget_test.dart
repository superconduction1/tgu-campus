// 一个最小的 widget 冒烟测试。
//
// 除了验证组件本身，它还有个副作用：`flutter create .` 只在缺少
// `test/widget_test.dart` 时才生成那个引用 `MyApp` 的模板文件；
// 我们已经有这个文件，CI 里就不会被塞进一个编译不过的模板。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgu_campus/features/urp/urp_widgets.dart';

void main() {
  testWidgets('空态组件把标题和说明都渲染出来', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UrpEmptyView(
            icon: Icons.inbox_outlined,
            title: '眼下没有待办',
            detail: '学分确认、学业预警都会出现在这里',
          ),
        ),
      ),
    );

    expect(find.text('眼下没有待办'), findsOneWidget);
    expect(find.text('学分确认、学业预警都会出现在这里'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}
