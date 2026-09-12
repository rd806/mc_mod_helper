import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/model/author.dart';
import 'package:mc_mod_helper/model/mod/mod_detail.dart';
import 'package:mc_mod_helper/model/mod/mod_summary.dart';
import 'package:mc_mod_helper/service/agent/agent.dart';
import 'package:mc_mod_helper/service/agent/history.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/widget/handler/agent_sheet.dart';

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

/// mcmod 搜索结果(两条):用于验证"当前模组被排除出候选"
http.Response _mcmodSearchPair(String keyword) => http.Response.bytes(
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
  <div class="modlist-block">
    <div class="title">
      <p class="name"><a href="/class/1234.html">[REI] REI物品管理器</a></p>
      <p class="ename"><a href="/class/1234.html">Roughly Enough Items</a></p>
    </div>
    <div class="cover"><img src="//i.mcmod.cn/rei.png"></div>
    <div class="intro-content"><span>类似 JEI 的物品查看模组</span></div>
  </div>
</body></html>'''),
  200,
);

void main() {
  setUp(() async {
    AgentApi.clearCaches();
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    // 搜索走哪个来源由 DisplaySettings 决定
    await DisplaySettings.instance.load();
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

  test('AgentModContext:正文去标签转纯文本,资料块含各字段', () {
    final ctx = AgentModContext.fromDetail(
      ModDetail(
        id: 'jei',
        source: ModSource.modrinth,
        title: 'JEI',
        subName: 'Just Enough Items',
        description: '查看物品合成',
        authors: const [Author(name: 'mezz', role: '所有者')],
        platform: 'Fabric',
        mcVersions: const {
          'fabric': ['1.21.1', '1.20.4'],
        },
        body: '<h2>简介</h2><script>忽略我</script><p>查看物品的合成配方与用途。</p>',
      ),
    );

    expect(ctx.key, 'modrinth:jei');
    final text = ctx.toPromptText();
    expect(text, contains('标题:JEI'));
    expect(text, contains('英文名:Just Enough Items'));
    expect(text, contains('简介:查看物品合成'));
    expect(text, contains('作者:mezz'));
    expect(text, contains('支持平台:Fabric'));
    expect(text, contains('支持版本:fabric 1.21.1/1.20.4'));
    expect(text, contains('查看物品的合成配方与用途。'));
    expect(text, isNot(contains('忽略我'))); // script 内容丢弃
    expect(text, isNot(contains('<p>'))); // 标签已去掉
  });

  test('AgentModContext:超长正文截断到上限', () {
    final long = '啊' * (AgentModContext.maxBodyChars + 500);
    final ctx = AgentModContext.fromDetail(
      ModDetail(
        id: 'x',
        source: ModSource.mcmod,
        title: 'X',
        body: '<p>$long</p>',
      ),
    );
    final text = ctx.toPromptText();
    expect(text, contains('…'));
    expect(text.length, lessThan(AgentModContext.maxBodyChars + 200));
  });

  test('带模组上下文:系统提示附上资料,且候选排除当前模组', () async {
    String? system;
    AgentApi.clientFactory = () => MockClient((request) async {
      final messages =
          (jsonDecode(request.body) as Map<String, dynamic>)['messages']
              as List;
      system = (messages.first as Map)['content'] as String;
      return _chat('{"reply": "给你找了几个", "search": ["物品查看"]}');
    });
    McmodApi.clientFactory = () =>
        MockClient((request) async => _mcmodSearchPair('物品查看'));

    final reply = await AgentApi.ask(
      const [AgentMessage(fromUser: true, text: '推荐跟它相似的模组')],
      mod: const AgentModContext(
        id: '459',
        source: ModSource.mcmod,
        title: '[JEI] JEI物品管理器',
        body: '查看物品的合成与用途',
      ),
    );

    // 系统提示里带上了当前模组资料
    expect(system, contains('当前用户正在浏览的模组资料'));
    expect(system, contains('[JEI] JEI物品管理器'));
    expect(system, contains('查看物品的合成与用途'));
    // 搜索命中两条,当前模组(459)被排除,只剩另一个
    expect(reply.mods, hasLength(1));
    expect(reply.mods.single.id, '1234');
    expect(reply.mods.single.title, '[REI] REI物品管理器');
  });

  test('不带模组上下文:系统提示不含资料块', () async {
    String? system;
    AgentApi.clientFactory = () => MockClient((request) async {
      final messages =
          (jsonDecode(request.body) as Map<String, dynamic>)['messages']
              as List;
      system = (messages.first as Map)['content'] as String;
      return _chat('{"reply": "你好", "search": []}');
    });

    await AgentApi.ask(const [AgentMessage(fromUser: true, text: '你好')]);
    expect(system, isNot(contains('当前用户正在浏览的模组资料')));
  });

  test('对话标题取首条用户消息,助手回复不参与', () async {
    final service = AgentHistoryService.instance;
    await service.add(
      AgentChatItem.assistant('欢迎', mods: const []), // 助手先说话
    );
    expect(service.current?.title, isEmpty);
    await service.add(AgentChatItem.user('能看合成配方的模组'));
    expect(service.current?.title, '能看合成配方的模组');
    // 超长标题截断
    await service.add(AgentChatItem.user('另一条很长的用户消息' * 3));
    expect(service.current?.title, '能看合成配方的模组');
  });

  test('startNew:当前对话为空时复用,不堆空对话', () {
    final service = AgentHistoryService.instance;
    final a = service.startNew();
    final b = service.startNew();
    expect(b.id, a.id);
    expect(service.conversations, hasLength(1));
  });

  test('多对话:select 切换,delete 删除后落到最近一个', () async {
    final service = AgentHistoryService.instance;
    await service.add(AgentChatItem.user('第一段对话'));
    final first = service.currentId!;
    service.startNew();
    await service.add(AgentChatItem.user('第二段对话'));
    final second = service.currentId!;
    expect(second, isNot(first));
    expect(service.conversations, hasLength(2));
    // 最近使用的排最前
    expect(service.conversations.first.id, second);

    service.select(first);
    expect(service.items.single.text, '第一段对话');
    // 无效 id 忽略
    service.select('不存在');
    expect(service.currentId, first);

    await service.delete(second);
    expect(service.conversations, hasLength(1));
    expect(service.items.single.text, '第一段对话');
    expect(service.currentId, first);
  });

  test('对话数量超上限时丢弃最旧的', () async {
    final service = AgentHistoryService.instance;
    for (var i = 0; i < AgentHistoryService.maxConversations + 5; i++) {
      await service.add(AgentChatItem.user('对话 $i'));
      service.startNew();
    }
    expect(service.conversations.length, AgentHistoryService.maxConversations);
    // 最新的空对话还在,最早的「对话 0」已被丢弃
    expect(service.items, isEmpty);
    expect(service.conversations.any((c) => c.title == '对话 0'), isFalse);
  });

  test('旧存档(扁平消息列表)迁移成一个对话', () async {
    SharedPreferences.setMockInitialValues({
      'agent_history': jsonEncode([
        AgentChatItem.user('能看合成配方的模组').toJson(),
        AgentChatItem.assistant('推荐 JEI').toJson(),
      ]),
    });
    await AgentHistoryService.instance.load();

    final service = AgentHistoryService.instance;
    expect(service.conversations, hasLength(1));
    expect(service.conversations.single.length, 2);
    expect(service.conversations.single.title, '能看合成配方的模组');
    expect(service.items, hasLength(2));
    expect(service.items.last.text, '推荐 JEI');
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

  testWidgets('重开面板:新开一个对话,可从历史对话切回', (tester) async {
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

    // 关掉再打开(面板已无「关闭」按钮,点面板外的遮罩收起):
    // 新开一个对话,看不到上一轮消息
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openSheet();
    expect(find.text('推荐 JEI'), findsNothing);
    expect(find.textContaining('有没有优化游戏帧数'), findsOneWidget);

    // 历史对话里能看到上一轮(标题取首条用户消息),点进去切回来
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    expect(find.text('历史对话'), findsOneWidget);
    expect(find.text('能看合成配方的模组'), findsOneWidget);
    await tester.tap(find.text('能看合成配方的模组'));
    await tester.pumpAndSettle();
    expect(find.text('历史对话'), findsNothing); // 回到消息列表
    expect(find.text('推荐 JEI'), findsOneWidget);
    expect(find.text('[JEI] JEI物品管理器'), findsOneWidget);
  });

  testWidgets('历史对话:可删除某个对话,当前对话可清空', (tester) async {
    // 直接种两段对话,省去重复走发送流程
    final service = AgentHistoryService.instance;
    await service.add(AgentChatItem.user('第一段对话'));
    service.startNew();
    await service.add(AgentChatItem.user('第二段对话'));

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
    // 打开面板会再开一个空对话,历史列表里因此有 3 条
    await tester.tap(find.text('打开助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    expect(find.text('第一段对话'), findsOneWidget);
    expect(find.text('第二段对话'), findsOneWidget);
    expect(find.text('新对话'), findsOneWidget);

    // 删掉「第二段对话」(删除按钮在对应行内,按标题定位避免误删)
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('第二段对话'),
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('将删除「第二段对话」'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('第二段对话'), findsNothing);
    expect(service.conversations, hasLength(2));

    // 切回「第一段对话」并清空它的消息
    await tester.tap(find.text('第一段对话'));
    await tester.pumpAndSettle();
    expect(find.text('第一段对话'), findsOneWidget); // 已显示为消息气泡
    expect(find.byTooltip('历史对话'), findsOneWidget); // 回到消息列表
    await tester.tap(find.byTooltip('清空当前对话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('将删除本对话的全部消息'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有没有优化游戏帧数'), findsOneWidget); // 空态
    expect(service.items, isEmpty);
    expect(service.conversations, hasLength(2)); // 对话本身保留
  });
}
