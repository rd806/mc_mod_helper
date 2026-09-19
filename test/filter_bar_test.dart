import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/widget/filter/filter_bar.dart';

/// 一屏筛选栏:分类/版本各几条,选项已加载完成(不涉及请求)
Widget _bar({int categories = 4, int versions = 4}) {
  return MaterialApp(
    home: Scaffold(
      body: FilterBar(
        filter: const Filter(
          type: ProjectType.mod,
          modSource: ModSource.mcmod,
          sortMethod: SortMethod.none,
        ),
        categories: [
          for (var i = 0; i < categories; i++)
            ProjectCategory(
              id: '$i',
              type: ProjectType.mod,
              name: '分类$i',
              source: ModSource.mcmod,
            ),
        ],
        versions: [
          for (var i = 0; i < versions; i++)
            ProjectVersion(version: '1.20.$i', source: ModSource.mcmod),
        ],
        onChanged: (_, _, _) {},
      ),
    ),
  );
}

void main() {
  testWidgets('展开与收起都有过渡:面板高度逐帧变化,不是一步到位', (tester) async {
    await tester.pumpWidget(_bar());
    await tester.pump();

    final bar = find.byType(FilterBar);
    final collapsed = tester.getSize(bar).height;

    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pump(); // 起手帧
    await tester.pump(const Duration(milliseconds: 60)); // 动画途中
    final expanding = tester.getSize(bar).height;
    await tester.pumpAndSettle();
    final expanded = tester.getSize(bar).height;

    expect(expanding, greaterThan(collapsed), reason: '已经开始长高');
    expect(expanding, lessThan(expanded), reason: '还没长完 —— 一口气到位说明只有高度跳变,没有动画');

    await tester.tap(find.byTooltip('收起筛选'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final collapsing = tester.getSize(bar).height;
    expect(collapsing, lessThan(expanded), reason: '已经开始变矮');
    expect(collapsing, greaterThan(collapsed), reason: '还没收完');

    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, collapsed);
  });

  testWidgets('收起时选项藏起来,展开后每个选项只命中一次', (tester) async {
    await tester.pumpWidget(_bar());
    await tester.pump();

    // 收起:面板用 Offstage 藏在树上(保留测量结果),查找与无障碍都跳过它。
    // 拿面板最后一组「排序」的标题当探针(它只在面板里出现)
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('排序'), findsNothing);

    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();

    // 每个选项只出现一次:CollapsibleWidgets 的测量层若用 Opacity(0) 藏,
    // 这份影子副本会让下面的数量全部翻倍
    expect(find.widgetWithText(ChoiceChip, '分类0'), findsOneWidget);
    // 4 分类 + 全部、4 版本 + 全部、3 排序
    expect(find.byType(ChoiceChip), findsNWidgets(13));
  });
}
