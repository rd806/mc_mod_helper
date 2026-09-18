import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/icon/link_icons.dart';
import 'package:mc_mod_helper/model/project/project_detail.dart';
import 'package:mc_mod_helper/model/project/project_loader.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/widget/detail/environment_card.dart';

Widget _card(Map<ProjectLoader, List<String>> versions) {
  return MaterialApp(
    home: Scaffold(
      body: EnvironmentCard(
        mod: ProjectDetail(
          id: 'sodium',
          type: ProjectType.mod,
          title: 'Sodium',
          source: ModSource.modrinth,
          sides: const ['required', 'unsupported'],
          mcVersions: versions,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('加载器行:图标与名称都来自 ModLoader,未知加载器保留原名', (tester) async {
    await tester.pumpWidget(
      _card({
        ProjectLoader.of('fabric'): ['1.21.1'],
        ProjectLoader.of('数据包'): ['1.20.1'],
      }),
    );
    await tester.pumpAndSettle();

    // 规范名称与图标(图标取自注册表:一份定义,界面与链接图标共用)
    expect(find.text('Fabric'), findsOneWidget);
    expect(find.byIcon(LinkIcons.fabric), findsOneWidget);
    // 注册表外的加载器不丢:原名照常显示,用通用图标
    expect(find.text('数据包'), findsOneWidget);
    expect(find.byIcon(Icons.extension), findsOneWidget);
    // 两组各自的版本都在
    expect(find.text('1.21.1'), findsOneWidget);
    expect(find.text('1.20.1'), findsOneWidget);
  });

  testWidgets('没有版本分组时整块不渲染', (tester) async {
    await tester.pumpWidget(_card(const {}));
    await tester.pumpAndSettle();
    expect(find.byIcon(LinkIcons.fabric), findsNothing);
  });
}
