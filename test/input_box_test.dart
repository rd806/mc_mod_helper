import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/widget/handler/input_box.dart';

/// 把 InputBox 放进最小页面,用 [onSaved] 接住回写值
Widget _wrap({
  required String value,
  required ValueChanged<String> onSaved,
  String hint = '占位提示',
  bool obscure = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: InputBox(
        title: '接口地址',
        value: value,
        hint: hint,
        obscure: obscure,
        onSaved: onSaved,
      ),
    ),
  );
}

void main() {
  testWidgets('点击行内配置:弹窗出现在屏幕中间并预填当前值,确定后回写', (tester) async {
    String? saved;
    await tester.pumpWidget(
      _wrap(value: 'https://a.example/v1', onSaved: (v) => saved = v),
    );

    // 未点击时只有行内展示,没有弹窗
    expect(find.text('https://a.example/v1'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // 弹窗居中(与页面中心重合)
    expect(
      tester.getCenter(find.byType(AlertDialog)),
      tester.getCenter(find.byType(Scaffold)),
    );
    // 输入框预填当前值
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'https://a.example/v1',
    );

    await tester.enterText(find.byType(TextField), 'https://b.example/v1');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(saved, 'https://b.example/v1');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('取消不回写;清空后确定回写空串(由调用方回落到默认)', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      _wrap(value: 'https://a.example/v1', onSaved: saved.add),
    );

    // 改内容后取消:不写回
    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://c.example/v1');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);

    // 清空后确定:回写空串(空值不等于取消)
    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(saved, ['']);
  });

  testWidgets('值为空时行内展示占位提示', (tester) async {
    await tester.pumpWidget(_wrap(value: '', hint: '未配置', onSaved: (_) {}));
    expect(find.text('未配置'), findsOneWidget);
  });

  testWidgets('遮蔽项:行内显示圆点,输入框默认遮蔽,眼睛可切换', (tester) async {
    await tester.pumpWidget(
      _wrap(value: 'sk-123456', obscure: true, onSaved: (_) {}),
    );
    // 行内不出现明文,按长度显示圆点
    expect(find.text('sk-123456'), findsNothing);
    expect(find.text('•' * 9), findsOneWidget);

    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );

    // 点眼睛 → 临时显示明文
    await tester.tap(find.byTooltip('显示'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
    expect(find.text('sk-123456'), findsOneWidget);
  });
}
