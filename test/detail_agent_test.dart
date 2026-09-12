import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/page/more/description.dart';
import 'package:mc_mod_helper/service/agent/agent.dart';
import 'package:mc_mod_helper/service/agent/history.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';

http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 助手回复
http.Response _chat(String content) => _json({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
});

/// Modrinth 详情页的三个接口(项目详情/版本列表/成员列表)
Future<http.Response> _modrinth(http.Request request) async {
  if (request.url.path == '/v2/project/jei') {
    return _json({
      'title': 'JEI',
      'body': '<h2>简介</h2><p>查看物品的合成配方与用途。</p>',
      'icon_url': null,
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
  if (request.url.path == '/v2/project/jei/members') {
    return _json([
      {
        'user': {'username': 'mezz'},
        'role': 'Owner',
      },
    ]);
  }
  return http.Response('not found', 404);
}

/// Modrinth 搜索:既返回当前项目(jei)也返回另一个同类项目
http.Response _search() => _json({
  'hits': [
    {
      'slug': 'jei',
      'title': '[JEI] JEI物品管理器',
      'description': '查看物品的合成与用途',
      'icon_url': null,
      'downloads': 100,
      'follows': 10,
    },
    {
      'slug': 'sodium',
      'title': 'Sodium',
      'description': '高性能渲染引擎',
      'icon_url': null,
      'downloads': 200,
      'follows': 20,
    },
  ],
  'total_hits': 2,
});

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_agent_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
    // 详情页加载成功会记一条浏览历史,同样先建库(生产环境由 main() 完成)
    await HistoryService.instance.init(dbPath: '${dir.path}/history.db');
  });

  setUp(() async {
    AgentApi.clearCaches();
    ModrinthApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await DisplaySettings.instance.load();
    await AgentSettings.instance.load();
    await AgentHistoryService.instance.load();
    AgentSettings.instance
      ..setApiKey('test-key')
      ..setBaseUrl('https://api.example.com/v1')
      ..setModel('test-model');
    // 详情与搜索都走 Modrinth:搜索结果里才能出现"当前项目自己"
    DisplaySettings.instance.setDataSource(ModSource.modrinth);
    ModrinthApi.clientFactory = () => MockClient((request) async {
      if (request.url.path == '/v2/search') return _search();
      return _modrinth(request);
    });
  });

  /// 打开详情页并推过三个接口的 1s 节流
  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailPage(
          id: 'jei',
          source: ModSource.modrinth,
          initialTitle: 'JEI',
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 打开助手面板
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('模组助手'));
    await tester.pumpAndSettle();
  }

  /// 点快捷指令 → 请求 → 搜索结果 → 渲染
  Future<void> tapQuickAction(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 搜索节流
    await tester.pump();
  }

  testWidgets('详情页助手:加载完成前无入口,加载后可打开并带出模组资料', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailPage(
          id: 'jei',
          source: ModSource.modrinth,
          initialTitle: 'JEI',
        ),
      ),
    );
    // 详情未加载完:没有可总结的内容,不显示助手入口
    expect(find.byTooltip('模组助手'), findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('模组助手'), findsOneWidget);

    await openSheet(tester);
    // 面板带出当前模组:空态提示 + 两个快捷指令 + 针对模组的输入提示
    expect(find.text('模组助手'), findsOneWidget);
    expect(find.textContaining('正在浏览「JEI」'), findsOneWidget);
    expect(find.text('总结这个模组'), findsOneWidget);
    expect(find.text('推荐相似模组'), findsOneWidget);
    expect(find.textContaining('问问关于这个模组的'), findsOneWidget);
  });

  testWidgets('总结这个模组:请求带上正文,回复无需候选卡片', (tester) async {
    String? system;
    AgentApi.clientFactory = () => MockClient((request) async {
      final messages =
          (jsonDecode(request.body) as Map<String, dynamic>)['messages']
              as List;
      system = (messages.first as Map)['content'] as String;
      // 末条是本轮用户消息(快捷指令原文)
      expect((messages.last as Map)['content'], '总结这个模组的内容');
      return _chat('{"reply": "JEI 用于查看物品的合成配方。", "search": []}');
    });

    await pumpDetail(tester);
    await openSheet(tester);
    await tapQuickAction(tester, '总结这个模组');

    // 系统提示里有当前模组的标题与正文(HTML 已转纯文本)
    expect(system, contains('标题:JEI'));
    expect(system, contains('查看物品的合成配方与用途。'));
    expect(system, isNot(contains('<p>')));
    // 对话里出现用户提问与助手回复
    expect(find.text('总结这个模组的内容'), findsOneWidget);
    expect(find.text('JEI 用于查看物品的合成配方。'), findsOneWidget);
  });

  testWidgets('推荐相似模组:给出候选卡片,且排除当前模组自己', (tester) async {
    AgentApi.clientFactory = () => MockClient(
      (request) async => _chat('{"reply": "可以看看这些", "search": ["渲染优化"]}'),
    );

    await pumpDetail(tester);
    await openSheet(tester);
    await tapQuickAction(tester, '推荐相似模组');

    expect(find.text('可以看看这些'), findsOneWidget);
    // 搜索命中两条:当前项目 jei 被排除,只剩 Sodium 的卡片
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('[JEI] JEI物品管理器'), findsNothing);
  });

  testWidgets('点候选卡片:收起面板并打开该模组详情页', (tester) async {
    AgentApi.clientFactory = () => MockClient(
      (request) async => _chat('{"reply": "可以看看这些", "search": ["渲染优化"]}'),
    );

    await pumpDetail(tester);
    await openSheet(tester);
    await tapQuickAction(tester, '推荐相似模组');

    await tester.tap(find.text('Sodium'));
    await tester.pumpAndSettle();
    expect(find.text('模组助手'), findsNothing); // 面板已收起
    expect(find.text('Sodium'), findsWidgets); // 新详情页标题
  });
}
