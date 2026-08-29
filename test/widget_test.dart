import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/main.dart';

void main() {
  testWidgets('应用启动并显示搜索页', (WidgetTester tester) async {
    await tester.pumpWidget(const McModApp());
    // 测试环境中网络请求被禁用(返回 HTTP 400),
    // 首页推荐加载失败后应显示错误提示,搜索框始终可用
    await tester.pumpAndSettle();

    expect(find.text('MC百科 · 模组搜索'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
  });
}
