import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/model/mod/mod_summary.dart';
import 'package:mc_mod_helper/service/agent/agent.dart';
import 'package:mc_mod_helper/service/agent/history.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/settings.dart';
import 'package:mc_mod_helper/widget/agent/agent_sheet.dart';

http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 助手回复内容
http.Response _chat(String content) => _json({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
});

/// mcmod 列表页搜索结果的假响应(结构与 _parseModlist 一致:
/// .title 里放 p.name/p.ename,.cover img,.intro-content span)
http.Response _mcmodSearch(String keyword) => http.Response.bytes(
  utf8.encode('''
<html><body>
  <div class="modlist-block">
    <div class="title">
      <p class="name"><a href="/class/459.html">[JEI] JEI物品管理器</a></p>
      <p class="ename"><a href="/class/459.html">Just Enough Items</a></p>
    </div>
    <div class="cover"><img src="//i.mcmod.cn/jei.png"></div>
    <div class="intro-content"><span>查看物品的合成与用途</span></div>
  </div>
</body></html>'''),
  200,
);

void main() {
  setUp(() async {
    AgentApi.clearCaches();
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    // 对话记录是单例:空 mock 存储 + load 把它复位(与设置服务同理)
    await AgentHistoryService.instance.load();
    await AgentSettings.instance.load();
    AgentSettings.instance
      ..setApiKey('test-key')
      ..setBaseUrl('https://api.example.com/v1')
      ..setModel('test-model');
  });

  test('解析 JSON 回复并执行搜索,返回候选模组', () async {
    final prompts = <String>[];
    AgentApi.clientFactory = () => MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      prompts.add((messages.first as Map)['content'] as String);
      // 首条是 system 提示,末条是本轮用户消息
      expect((messages.last as Map)['role'], 'user');
      return _chat('{"reply": "推荐 JEI", "search": ["JEI", "物品管理器"]}');
    });
    McmodApi.clientFactory = () => MockClient(
      (request) async => _mcmodSearch(request.url.queryParameters['key'] ?? ''),
    );

    final reply = await AgentApi.ask(const [
      AgentMessage(fromUser: true, text: '能看合成配方的模组'),
    ]);

    expect(reply.text, '推荐 JEI');
    // 两个关键词都搜索,但结果按 来源:id 去重
    expect(reply.mods, hasLength(1));
    expect(reply.mods.single.title, '[JEI] JEI物品管理器');
    // 系统提示里包含 JSON 协议要求
    expect(prompts.single, contains('"search"'));
  });

  test('search 为空时不搜索,按纯聊天回复', () async {
    var searched = false;
    AgentApi.clientFactory = () =>
        MockClient((request) async => _chat('{"reply": "你好", "search": []}'));
    McmodApi.clientFactory = () => MockClient((request) async {
      searched = true;
      return _mcmodSearch('x');
    });

    final reply = await AgentApi.ask(const [
      AgentMessage(fromUser: true, text: '你好'),
    ]);
    expect(reply.text, '你好');
    expect(reply.mods, isEmpty);
    expect(searched, isFalse);
  });

  test('输出带代码围栏/多余文字时仍能解析', () async {
    AgentApi.clientFactory = () => MockClient(
      (request) async =>
          _chat('好的,这是结果:\n```json\n{"reply": "给你找了", "search": ["JEI"]}\n```'),
    );
    McmodApi.clientFactory = () =>
        MockClient((request) async => _mcmodSearch('JEI'));

    final reply = await AgentApi.ask(const [
      AgentMessage(fromUser: true, text: '找 JEI'),
    ]);
    expect(reply.text, '给你找了');
    expect(reply.mods, isNotEmpty);
  });

  test('无法解析 JSON 时退化为纯文本回复', () async {
    AgentApi.clientFactory = () =>
        MockClient((request) async => _chat('我暂时不明白你的意思'));
    final reply = await AgentApi.ask(const [
      AgentMessage(fromUser: true, text: '???'),
    ]);
    expect(reply.text, '我暂时不明白你的意思');
    expect(reply.mods, isEmpty);
  });

  test('未配置 API Key:抛引导异常', () async {
    AgentSettings.instance.setApiKey('');
    await expectLater(
      AgentApi.ask(const [AgentMessage(fromUser: true, text: '找模组')]),
      throwsA(isA<AgentNotConfiguredException>()),
    );
  });

  test('对话记录持久化:重新读取后消息与候选模组都在', () async {
    final service = AgentHistoryService.instance;
    await service.add(AgentChatItem.user('能看合成配方的模组'));
    await service.add(
      AgentChatItem.assistant(
        '推荐 JEI',
        mods: const [
          ModSummary(
            id: '459',
            title: '[JEI] JEI物品管理器',
            description: '查看物品的合成与用途',
            subName: 'Just Enough Items',
            source: ModSource.mcmod,
          ),
        ],
      ),
    );

    // 模拟重启:重新从存储读取(不经过内存)
    await service.load();
    final items = service.items;
    expect(items, hasLength(2));
    expect(items.first.fromUser, isTrue);
    expect(items.first.text, '能看合成配方的模组');
    expect(items.last.fromUser, isFalse);
    expect(items.last.text, '推荐 JEI');
    final mod = items.last.mods.single;
    expect(mod.id, '459');
    expect(mod.title, '[JEI] JEI物品管理器');
    expect(mod.subName, 'Just Enough Items');
    expect(mod.source, ModSource.mcmod);

    // 清空后重新读取:存储里的记录一并删除
    await service.clear();
    await service.load();
    expect(service.items, isEmpty);
  });

  test('对话记录条目数超上限时丢弃最早的', () async {
    final service = AgentHistoryService.instance;
    for (var i = 0; i < AgentHistoryService.maxItems + 5; i++) {
      await service.add(AgentChatItem.user('第 $i 条'));
    }
    expect(service.items, hasLength(AgentHistoryService.maxItems));
    expect(service.items.first.text, '第 5 条');
    expect(service.items.last.text, '第 104 条');
  });

  testWidgets('对话面板:发送后显示回复与候选卡片,点卡片进详情', (tester) async {
    AgentApi.clientFactory = () => MockClient(
      (request) async => _chat('{"reply": "推荐 JEI", "search": ["JEI"]}'),
    );
    McmodApi.clientFactory = () =>
        MockClient((request) async => _mcmodSearch('JEI'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgentSheet(context),
              child: const Text('打开助手'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开助手'));
    await tester.pumpAndSettle();

    expect(find.text('模组助手'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '能看合成配方的模组');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    // 请求 → 搜索 → 渲染(含 mcmod 节流不影响:直接返回假响应)
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('推荐 JEI'), findsOneWidget);
    expect(find.text('[JEI] JEI物品管理器'), findsOneWidget);

    // 点候选卡片:面板关闭并进入详情页(标题栏显示初始标题)
    await tester.tap(find.text('[JEI] JEI物品管理器'));
    await tester.pumpAndSettle();
    expect(find.text('模组助手'), findsNothing);
    expect(find.text('[JEI] JEI物品管理器'), findsWidgets); // 详情页 AppBar 标题
  });

  testWidgets('关闭面板再打开:对话记录仍在,可一键清空', (tester) async {
    AgentApi.clientFactory = () => MockClient(
      (request) async => _chat('{"reply": "推荐 JEI", "search": ["JEI"]}'),
    );
    McmodApi.clientFactory = () =>
        MockClient((request) async => _mcmodSearch('JEI'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgentSheet(context),
              child: const Text('打开助手'),
            ),
          ),
        ),
      ),
    );
    Future<void> openSheet() async {
      await tester.tap(find.text('打开助手'));
      await tester.pumpAndSettle();
    }

    await openSheet();
    await tester.enterText(find.byType(TextField), '能看合成配方的模组');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('推荐 JEI'), findsOneWidget);

    // 关掉面板(记录已落到服务里)再打开:历史与候选卡片都还在
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('推荐 JEI'), findsNothing);
    await openSheet();
    expect(find.text('推荐 JEI'), findsOneWidget);
    expect(find.text('[JEI] JEI物品管理器'), findsOneWidget);
    expect(find.textContaining('有没有优化游戏帧数'), findsNothing);

    // 清空:确认对话框 → 回到空态提示
    await tester.tap(find.byTooltip('清空对话'));
    await tester.pumpAndSettle();
    expect(find.text('将删除全部对话记录与候选模组,且无法恢复。'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('推荐 JEI'), findsNothing);
    expect(find.textContaining('有没有优化游戏帧数'), findsOneWidget);
    expect(AgentHistoryService.instance.items, isEmpty);
  });
}
