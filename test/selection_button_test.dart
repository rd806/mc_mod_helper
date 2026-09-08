import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/widget/detail/intro/selection_button.dart';

/// 详情页在 builder 里给整棵树注入 MediaQuery.textScaler(字体缩放),
/// 这里用同样方式包一层;其余与 _wrap 一致。
Widget _wrap(Widget child, {double scale = 1.0}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('preferredHeight 与组件实际高度一致', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SelectionButton(
          button: const [('介绍', 0), ('信息', 1)],
          selectedIndex: 0,
          switchTo: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 组件整体含 Card 外边距,以 SelectionButton 子树里的 Card 作为实际高度
    final card = find.descendant(
      of: find.byType(SelectionButton),
      matching: find.byType(Card),
    );
    final actual = tester.getSize(card).height;
    final expected = SelectionButton.preferredHeight(tester.element(card));
    expect(actual, closeTo(expected, 1));
  });

  testWidgets('放大字体后高度公式仍与实际一致(吸顶 extent 跟随字号)', (tester) async {
    // 与详情页一致的字体缩放注入
    await tester.pumpWidget(
      _wrap(
        SelectionButton(
          button: const [('介绍', 0), ('信息', 1)],
          selectedIndex: 0,
          switchTo: (_) {},
        ),
        scale: 1.5,
      ),
    );
    await tester.pumpAndSettle();

    final card = find.descendant(
      of: find.byType(SelectionButton),
      matching: find.byType(Card),
    );
    final actual = tester.getSize(card).height;
    final expected = SelectionButton.preferredHeight(tester.element(card));
    // 1.5 倍字后高度应明显大于默认(默认约 56)
    expect(expected, greaterThan(60));
    expect(actual, closeTo(expected, 1));
  });
}
