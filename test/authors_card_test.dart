import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/model/author/author_summary.dart';
import 'package:mc_mod_helper/model/project/project_detail.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/page/detail/author_page.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/widget/detail/authors_card.dart';

/// 一个带作者 id 的详情(点芯片要能进作者页)
const _project = ProjectDetail(
  id: '883',
  type: ProjectType.modpack,
  title: '剑拔弩张之时',
  source: ModSource.mcmod,
  authors: [
    AuthorSummary(name: '水咬狸花猫', id: '32946', role: '所有者/美术'),
    AuthorSummary(name: '钱多多', id: '34818', role: '程序'),
  ],
);

/// 作者 id 缺失时(理论上不会有)芯片保持纯展示
const _noIdProject = ProjectDetail(
  id: '1',
  type: ProjectType.mod,
  title: '测试模组',
  source: ModSource.mcmod,
  authors: [AuthorSummary(name: '古镇天', role: '所有者/程序')],
);

/// 作者页(只要头部能解析出来即可)
String _authorHtml() => '''
<html><body>
<div class="author-row">
  <div class="author-user-frame">
    <div class="author-user-avatar"><span><img src="//i.mcmod.cn/u/a.png"></span></div>
    <div class="author-name"><span class="name"><h5>水咬狸花猫</h5></span></div>
  </div>
</div>
</body></html>''';

Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

Widget _wrap(ProjectDetail project) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: AuthorsCard(project: project)),
  ),
);

void main() {
  setUp(() {
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('作者芯片可点:进作者页并带上 id 与来源', (tester) async {
    final uris = <Uri>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      return http.Response.bytes(utf8.encode(_authorHtml()), 200);
    });

    await tester.pumpWidget(_wrap(_project));
    // CollapsibleWidgets 首帧只渲染测量层,帧后测量完才显示内容
    await tester.pump();

    // 两个作者都有 id → 都是可点的 ActionChip
    expect(find.byType(ActionChip), findsNWidgets(2));

    await tester.tap(find.text('水咬狸花猫'));
    await _settle(tester);

    expect(find.byType(AuthorPage), findsOneWidget);
    // 走的是被点那个作者的作者页(名字与角色都带过去了)
    expect(uris.single.path, '/author/32946.html');
    expect(find.text('水咬狸花猫'), findsWidgets);
  });

  testWidgets('没有作者 id 时芯片不可点(仍是纯 Chip)', (tester) async {
    await tester.pumpWidget(_wrap(_noIdProject));
    await tester.pump(); // 等测量层量完,内容才显示

    expect(find.byType(ActionChip), findsNothing);
    expect(find.widgetWithText(Chip, '古镇天'), findsOneWidget);
  });
}
