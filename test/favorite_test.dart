import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/main.dart';
import 'package:mc_mod_helper/service/savings.dart';
import 'package:mc_mod_helper/service/settings.dart';
import 'package:mc_mod_helper/value/source.dart';

/// JSON 响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Modrinth 假响应:搜索 + 详情 + 版本列表
Future<http.Response> _handler(http.Request request) async {
  if (request.url.path == '/v2/search') {
    return _json({
      'hits': [
        {
          'slug': 'jei',
          'title': 'JEI',
          'description': 'Just Enough Items',
          'icon_url': null,
          'downloads': 100,
          'follows': 10,
        },
      ],
      'total_hits': 1,
    });
  }
  if (request.url.path == '/v2/project/jei') {
    return _json({
      'title': 'JEI',
      'body': 'Just Enough Items',
      'icon_url': null,
      'downloads': 1000000,
      'followers': 5000,
      'game_versions': ['1.21.1'],
      'loaders': ['fabric'],
      'client_side': 'required',
      'server_side': 'unsupported',
    });
  }
  if (request.url.path == '/v2/project/jei/version') {
    return _json([
      {
        'loaders': ['fabric'],
        'game_versions': ['1.21.1'],
      },
    ]);
  }
  return http.Response('not found', 404);
}

/// 启动应用并推过首页推荐/分类两个 400 请求(mcmod 真实客户端)
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const McModHelper());
  await tester.pump(); // 推荐请求 400 → setState
  await tester.pump(const Duration(seconds: 1)); // 节流计时器 → 分类请求发出
  await tester.pump(); // 分类 400 → setState
  await tester.pump(); // 渲染错误态
}

/// 搜索页签里搜索 jei 并等结果渲染(Modrinth 假响应,mcmod 真实 400)
Future<void> _searchJei(WidgetTester tester) async {
  await tester.tap(find.text('搜索'));
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'jei');
  await tester.tap(find.byIcon(Icons.arrow_forward));
  await tester.pump(); // 搜索发起
  await tester.pump(); // mcmod 400 → 失败;modrinth 命中
  await tester.pump(); // 渲染结果
}

void main() {
  setUpAll(() async {
    // 收藏页/ModTile 收藏按钮依赖收藏服务(生产环境由 main() 完成)
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
  });

  setUp(() async {
    McmodApi.clearCaches();
    ModrinthApi.clearCaches();
    ModrinthApi.clientFactory = () => MockClient(_handler);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    await FavoritesService.instance.clear();
  });

  testWidgets('收藏页展示已收藏条目(含次要名称),心形取消收藏', (tester) async {
    // 直接种一条收藏(搜索列表的 ModTile 不带心形,
    // 收藏入口在卡片/详情页,由其它用例覆盖)
    await FavoritesService.instance.add(
      Likes(
        id: 'jei',
        title: '[JEI] JEI物品管理器',
        description: '查看物品的合成与用途',
        subName: 'Just Enough Items',
        source: ModSource.mcmod,
        date: 1.0,
      ),
    );
    await _pumpApp(tester);

    // 切到收藏页签:条目出现,次要名称作为副标题显示
    await tester.tap(find.text('收藏'));
    await tester.pump();
    expect(find.text('JEI物品管理器'), findsOneWidget);
    expect(find.text('Just Enough Items'), findsOneWidget);
    expect(find.textContaining('还没有收藏'), findsNothing);
    // 心形已点亮
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.byIcon(Icons.favorite),
      ),
      findsOneWidget,
    );

    // 再点一次心形:取消收藏,回到空态提示
    await tester.tap(
      find.descendant(
        of: find.byType(Card),
        matching: find.byIcon(Icons.favorite),
      ),
    );
    await tester.pump();
    expect(FavoritesService.instance.list(), isEmpty);
    expect(find.textContaining('还没有收藏'), findsOneWidget);
  });

  testWidgets('详情页心形收藏/取消收藏一轮', (tester) async {
    await _pumpApp(tester);
    await _searchJei(tester);

    // 进详情页:两个请求(项目详情 + 版本列表)各等 1s 节流
    await tester.tap(find.text('JEI'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 节流 → 项目详情请求发出
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 节流 → 版本列表请求发出
    await tester.pump();
    await tester.pump();

    // 收藏:AppBar 空心 → 点亮(壳层的侧边栏在路由之下,不干扰)
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(FavoritesService.instance.list().length, 1);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.favorite),
      ),
      findsOneWidget,
    );

    // 取消收藏:点亮 → 空心
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.favorite),
      ),
    );
    await tester.pump();
    expect(FavoritesService.instance.list().length, 0);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );
  });
}
