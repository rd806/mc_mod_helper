import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/widget/common/selection_button.dart';

/// 应用在 main.dart 里给整棵树注入 MediaQuery.textScaler(全局字体缩放),
/// 这里用同样方式包一层。
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
    // 字号缩放的允许范围是 0.5~2.0(ThemeSettings.fontMin/fontMax),
    // 取默认、中间、上限三档:公式必须始终算得与实际布局一样高
    final heights = <double, double>{};

    for (final scale in [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        _wrap(
          SelectionButton(
            button: const [('介绍', 0), ('信息', 1)],
            selectedIndex: 0,
            switchTo: (_) {},
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();

      final card = find.descendant(
        of: find.byType(SelectionButton),
        matching: find.byType(Card),
      );
      final actual = tester.getSize(card).height;
      final expected = SelectionButton.preferredHeight(tester.element(card));
      expect(actual, closeTo(expected, 1), reason: '$scale 倍字号下公式应与实际高度一致');
      heights[scale] = expected;
    }

    // 上限字号下确实长高了(而不是被按钮最小高兜住),吸顶 extent 才算跟随字号
    expect(heights[2.0], greaterThan(heights[1.0]!));
  });
}
