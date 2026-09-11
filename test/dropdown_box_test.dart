import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/widget/common/dropdown_box.dart';

const _options = [
  DropdownOption('默认', 'a'),
  DropdownOption('最新收录', 'b'),
  DropdownOption('最新编辑', 'c'),
];

/// 把 DropdownBox 放进最小页面,用 [onChanged] 接住选中值
Widget _wrap({
  required String value,
  required ValueChanged<String> onChanged,
  List<DropdownOption<String>> options = _options,
  String? fallback,
}) {
  return MaterialApp(
    home: Scaffold(
      body: DropdownBox<String>(
        title: '推荐来源',
        value: value,
        options: options,
        fallback: fallback,
        onChanged: onChanged,
      ),
    ),
  );
}

void main() {
  testWidgets('展示当前选中项;选择其它项后回调其取值', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_wrap(value: 'b', onChanged: picked.add));

    // 行内看到的是当前值对应的文案
    expect(find.text('推荐来源'), findsOneWidget);
    expect(find.text('最新收录'), findsOneWidget);

    // 展开菜单:三项都出现(菜单项用 last 取,行内还留着一份当前值)
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('最新编辑'), findsOneWidget);

    await tester.tap(find.text('最新编辑').last);
    await tester.pumpAndSettle();
    expect(picked, ['c']);
  });

  testWidgets('选中值不在选项里:回落到第一项,不崩溃', (tester) async {
    await tester.pumpWidget(_wrap(value: '不存在', onChanged: (_) {}));
    // 回落第一项「默认」
    expect(find.text('默认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中值不在选项里:优先回落到指定的 fallback', (tester) async {
    await tester.pumpWidget(
      _wrap(value: '不存在', fallback: 'c', onChanged: (_) {}),
    );
    expect(find.text('最新编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选项可带前置图标', (tester) async {
    await tester.pumpWidget(
      _wrap(
        value: 'a',
        options: const [
          DropdownOption('默认', 'a', icon: Icon(Icons.home)),
          DropdownOption('最新收录', 'b', icon: Icon(Icons.star)),
        ],
        onChanged: (_) {},
      ),
    );
    expect(find.byIcon(Icons.home), findsOneWidget);
  });
}
