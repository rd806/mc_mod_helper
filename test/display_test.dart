import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/mod_summary.dart';
import 'package:mc_mod_helper/value/source.dart';
import 'package:mc_mod_helper/value/display.dart';
import 'package:mc_mod_helper/widget/mod/mod_card.dart';

/// 以给定宽度渲染展示方式对应的模组列表
Widget _wrap(DisplayStyle style, {double width = 800}) {
  final mods = [
    ModSummary(
      id: '1',
      title: '测试模组',
      description: '简介',
      source: ModSource.mcmod,
    ),
  ];
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: DisplayManager.buildSliver(style, mods),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('card:网格大卡片(ModCardColumn)', (tester) async {
    await tester.pumpWidget(_wrap(DisplayStyle.card));
    expect(find.byType(ModCardColumn), findsOneWidget);
    expect(find.byType(ModCardRow), findsNothing);
  });

  testWidgets('table:单行列表(ModCardRow)', (tester) async {
    await tester.pumpWidget(_wrap(DisplayStyle.table));
    expect(find.byType(ModCardRow), findsOneWidget);
    expect(find.byType(ModCardColumn), findsNothing);
  });

  testWidgets('auto:窄屏列表、宽屏网格', (tester) async {
    // 窄屏(< 480):列表
    await tester.pumpWidget(_wrap(DisplayStyle.auto, width: 400));
    expect(find.byType(ModCardRow), findsOneWidget);
    expect(find.byType(ModCardColumn), findsNothing);

    // 宽屏:网格
    await tester.pumpWidget(_wrap(DisplayStyle.auto, width: 800));
    expect(find.byType(ModCardColumn), findsOneWidget);
    expect(find.byType(ModCardRow), findsNothing);
  });

  testWidgets('空列表渲染空白,不报错', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: DisplayManager.buildSliver(DisplayStyle.card, const []),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(ModCardColumn), findsNothing);
    expect(find.byType(ModCardRow), findsNothing);
  });

  testWidgets('卡片显示次要名称:subName 优先,括号拆分兜底', (tester) async {
    // mcmod 列表页:标题无括号,次要名称在 subName 字段
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModCardRow(
            mod: ModSummary(
              id: '1',
              title: '[JEI] JEI物品管理器',
              description: '',
              subName: 'Just Enough Items',
              source: ModSource.mcmod,
            ),
          ),
        ),
      ),
    );
    expect(find.text('JEI物品管理器'), findsOneWidget);
    expect(find.text('Just Enough Items'), findsOneWidget);

    // 无 subName 时回退到标题括号拆分
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModCardRow(
            mod: ModSummary(
              id: '2',
              title: '模组名称 (English Name)',
              description: '',
              source: ModSource.mcmod,
            ),
          ),
        ),
      ),
    );
    expect(find.text('模组名称'), findsOneWidget);
    expect(find.text('English Name'), findsOneWidget);
  });
}
