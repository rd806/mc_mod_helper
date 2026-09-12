import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/page/recommend/default_list.dart';
import 'package:mc_mod_helper/page/recommend/feature_list_page.dart';
import 'package:mc_mod_helper/page/recommend/last_edit_list.dart';
import 'package:mc_mod_helper/page/recommend/last_publish_list.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

/// modlist 列表页的假响应:每页 [count] 个条目 + 分页链接(总 [totalPages] 页)
http.Response _modlist({
  required int page,
  int count = 20,
  int totalPages = 3,
}) {
  final blocks = List.generate(count, (i) {
    final id = (page - 1) * count + i + 1;
    return '''
  <div class="modlist-block">
    <div class="title">
      <p class="name"><a href="/class/$id.html">模组$id</a></p>
      <p class="ename"><a href="/class/$id.html">Mod $id</a></p>
    </div>
    <div class="cover"><img src="//i.mcmod.cn/$id.png"></div>
    <div class="intro-content"><span>第 $id 个模组</span></div>
  </div>''';
  }).join();
  final pages = List.generate(
    totalPages,
    (i) => '<a data-page="${i + 1}" href="?page=${i + 1}">${i + 1}</a>',
  ).join();
  return http.Response.bytes(
    utf8.encode(
      '<html><body>$blocks<div class="pagination">$pages</div>'
      '</body></html>',
    ),
    200,
  );
}

void main() {
  setUp(() async {
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await DisplaySettings.instance.load();
  });

  testWidgets('版块列表页:首屏第 1 页,滚到底自动加载下一页,到底后提示', (tester) async {
    final requestedPages = <String>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      requestedPages.add('$page');
      // 记录排序参数:最新收录应带 sort=createtime
      expect(request.url.queryParameters['sort'], 'createtime');
      return _modlist(page: page, totalPages: 2);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: FeatureListPage(source: FeatureSource.createTime, title: '最新收录'),
      ),
    );
    await tester.pump(); // 第 1 页请求 → 渲染

    expect(find.widgetWithText(AppBar, '最新收录'), findsOneWidget);
    expect(find.text('模组1'), findsOneWidget);
    expect(requestedPages, ['1']);

    // 滚到底:触发下一页(距底部 600px 内即可)。
    // 请求受 mcmod www 的 1s 节流约束,要推进假时钟才会真正发出
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // 响应 → setState
    expect(requestedPages, ['1', '2']);

    // 再滚到底:第二页的内容在列表尾部,最后一页提示到底且不再请求
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    expect(find.text('模组40'), findsOneWidget);
    expect(find.text('已经到底啦'), findsOneWidget);
    expect(requestedPages, ['1', '2']);
  });

  testWidgets('版块列表页:请求失败给出重试', (tester) async {
    McmodApi.clientFactory = () =>
        MockClient((request) async => http.Response('boom', 500));

    await tester.pumpWidget(
      const MaterialApp(
        home: FeatureListPage(source: FeatureSource.none, title: '默认排序'),
      ),
    );
    await tester.pump();

    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('三个版块入口页各自带着对应的排序方式', (tester) async {
    final recorded = <String, String>{};
    McmodApi.clientFactory = () => MockClient((request) async {
      final sort = request.url.queryParameters['sort'] ?? '';
      recorded[sort] = sort;
      return _modlist(page: 1, totalPages: 1);
    });

    for (final (page, title) in <(Widget, String)>[
      (const DefaultModPage(), '默认排序'),
      (const LastPublishModPage(), '最新收录'),
      (const LastEditModPage(), '最新编辑'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: page));
      // 请求受 mcmod www 的 1s 节流约束:推进假时钟让它发出
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.widgetWithText(AppBar, title), findsOneWidget);
    }

    // 默认排序 = 空 sort;另两个分别是 createtime / lastedittime
    expect(recorded.keys, containsAll(['', 'createtime', 'lastedittime']));
  });
}
