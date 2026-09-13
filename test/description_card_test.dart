import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/service/agent/translate.dart';
import 'package:mc_mod_helper/model/mod/mod_detail.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/widget/detail/card/description_card.dart';

http.Response _chat(String content) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _mod = ModDetail(
  id: '123',
  title: '测试模组',
  source: ModSource.mcmod,
  body: '<p>Original English text</p>',
);

/// 另一个模组:用于验证 State 被复用(详情页刷新/换模组)时译文不串台
const _otherMod = ModDetail(
  id: '456',
  title: '另一个模组',
  source: ModSource.mcmod,
  body: '<p>Other mod body</p>',
);

/// 中文正文:中文目标 + 中文正文时自动翻译应当跳过
const _zhMod = ModDetail(
  id: '789',
  title: '中文模组',
  source: ModSource.mcmod,
  body: '<p>本模组添加了大量新的物品与方块,并优化了合成配方。</p>',
);

/// 没有正文的模组(此时整张卡片不渲染)
const _emptyMod = ModDetail(id: '999', title: '空正文', source: ModSource.mcmod);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() async {
    TranslateApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await LanguageSettings.instance.load();
    await DisplaySettings.instance.load();
    await AgentSettings.instance.load();
  });

  testWidgets('手动翻译:点击显示译文,再点切回原文且不重复请求', (tester) async {
    AgentSettings.instance
      ..setApiKey('k')
      ..setBaseUrl('https://api.example.com/v1');
    var calls = 0;
    TranslateApi.clientFactory = () => MockClient((request) async {
      calls++;
      return _chat('<p>这是译文</p>');
    });

    await tester.pumpWidget(
      _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
    );

    // 初始:显示原文,按钮为「翻译」
    expect(
      find.textContaining('Original English text', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('翻译'), findsOneWidget);

    // 点翻译 → 请求 → 显示译文,按钮变「原文」
    await tester.tap(find.text('翻译'));
    await tester.pump(); // 发起请求 + loading
    await tester.pump(); // 响应回来
    expect(find.textContaining('这是译文', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Original English text', findRichText: true),
      findsNothing,
    );
    expect(find.text('原文'), findsOneWidget);
    expect(calls, 1);

    // 切回原文:不再请求
    await tester.tap(find.text('原文'));
    await tester.pump();
    expect(
      find.textContaining('Original English text', findRichText: true),
      findsOneWidget,
    );
    expect(calls, 1);

    // 再次翻译:命中缓存,仍不请求
    await tester.tap(find.text('翻译'));
    await tester.pump();
    expect(find.textContaining('这是译文', findRichText: true), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('未配置 API Key:提示去设置页,不发请求', (tester) async {
    var called = false;
    TranslateApi.clientFactory = () => MockClient((request) async {
      called = true;
      return _chat('<p>x</p>');
    });

    await tester.pumpWidget(
      _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
    );
    await tester.tap(find.text('翻译'));
    await tester.pump(); // SnackBar 入场

    expect(find.textContaining('尚未配置 AI 接口 Key'), findsOneWidget);
    expect(called, isFalse);
  });

  group('自动翻译', () {
    testWidgets('打开开关后进页面即出译文(无需点按钮)', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>这是译文</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);

      expect(find.textContaining('这是译文', findRichText: true), findsOneWidget);
      expect(find.text('原文'), findsOneWidget);
      expect(calls, 1);
    });

    testWidgets('未配置 Key:静默跳过,手动点才给引导', (tester) async {
      var called = false;
      TranslateApi.clientFactory = () => MockClient((request) async {
        called = true;
        return _chat('<p>x</p>');
      });
      // 只开开关,不配置 Key
      LanguageSettings.instance.setAutoTranslate(true);

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);

      // 用户没主动操作:既不请求也不弹提示(否则一进页面就被骚扰)
      expect(called, isFalse);
      expect(find.textContaining('尚未配置'), findsNothing);
      expect(
        find.textContaining('Original English text', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.text('翻译'));
      await tester.pump();
      expect(find.textContaining('尚未配置'), findsOneWidget);
    });

    testWidgets('进页面时未配置,填好 Key 返回后自动翻译', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>这是译文</p>');
      });
      LanguageSettings.instance.setAutoTranslate(true);

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);
      expect(calls, 0);

      // 用户去设置页填好 Key(详情页此时还活着),应自行开始翻译
      AgentSettings.instance.setApiKey('k');
      await _settle(tester);

      expect(calls, 1);
      expect(find.textContaining('这是译文', findRichText: true), findsOneWidget);
    });

    testWidgets('中途关掉开关:回到原文', (tester) async {
      TranslateApi.clientFactory = () =>
          MockClient((request) async => _chat('<p>这是译文</p>'));
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);
      expect(find.textContaining('这是译文', findRichText: true), findsOneWidget);

      LanguageSettings.instance.setAutoTranslate(false);
      await tester.pump();
      expect(
        find.textContaining('Original English text', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('翻译'), findsOneWidget);
    });

    testWidgets('以关闭状态进入后打开开关:立即翻译', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>这是译文</p>');
      });
      AgentSettings.instance.setApiKey('k');

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);
      expect(calls, 0);

      LanguageSettings.instance.setAutoTranslate(true);
      await _settle(tester);
      expect(calls, 1);
    });

    testWidgets('换目标语言:按新语言重新翻译', (tester) async {
      var calls = 0;
      // 按提示词里的目标语言返回不同译文
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final prompt =
            ((body['messages'] as List).first as Map)['content'] as String;
        return _chat(
          prompt.contains('英语') ? '<p>english translation</p>' : '<p>中文译文</p>',
        );
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);
      expect(find.textContaining('中文译文', findRichText: true), findsOneWidget);

      LanguageSettings.instance.setTranslateLang('en');
      await _settle(tester);

      expect(calls, 2);
      expect(
        find.textContaining('english translation', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('手动切到原文后,无关的设置变化不会把它拉回译文', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>这是译文</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);

      await tester.tap(find.text('原文'));
      await tester.pump();
      expect(
        find.textContaining('Original English text', findRichText: true),
        findsOneWidget,
      );

      // 改模型名会触发一次设置通知:但用户的「看原文」选择应当保持
      AgentSettings.instance.setModel('another-model');
      await tester.pump();
      expect(
        find.textContaining('Original English text', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('这是译文', findRichText: true), findsNothing);
      expect(calls, 1);
    });

    testWidgets('失败:行内提示 + 点重试成功,且不自动重试', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('bad key', 401)
            : _chat('<p>重试后的译文</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);

      expect(find.textContaining('自动翻译失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 自动路径不弹 SnackBar(用户没主动操作,而且可能正待在设置页)
      expect(find.byType(SnackBar), findsNothing);

      // 再次的设置通知不会自动重试,免得对着坏 Key 反复请求
      AgentSettings.instance.setModel('another-model');
      await tester.pump();
      expect(calls, 1);

      await tester.tap(find.text('重试'));
      await _settle(tester);
      expect(find.textContaining('重试后的译文', findRichText: true), findsOneWidget);
      expect(find.textContaining('自动翻译失败'), findsNothing);
    });

    testWidgets('中文目标 + 中文正文:跳过自动翻译,手动点击照翻', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>这是译文</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _zhMod, onLinkTap: _noop)),
      );
      await _settle(tester);

      // 中文翻中文纯属白花 token
      expect(calls, 0);
      expect(
        find.textContaining('本模组添加了大量新的物品', findRichText: true),
        findsOneWidget,
      );

      // 手动路径不受该判断限制
      await tester.tap(find.text('翻译'));
      await _settle(tester);
      expect(calls, 1);
    });

    testWidgets('换模组后不复用上一个模组的译文', (tester) async {
      final prompts = <String>[];
      TranslateApi.clientFactory = () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        prompts.add(
          ((body['messages'] as List).first as Map)['content'] as String,
        );
        return _chat('<p>这是译文</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _mod, onLinkTap: _noop)),
      );
      await _settle(tester);
      expect(prompts, hasLength(1));
      expect(prompts.single, contains('Original English text'));

      // 同一个位置换成另一个模组:element 相同、State 被复用
      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _otherMod, onLinkTap: _noop)),
      );
      await _settle(tester);

      // 必须为新模组重新请求,而不是把上一个模组的译文留在正文位置
      expect(prompts, hasLength(2));
      expect(prompts.last, contains('Other mod body'));
    });

    testWidgets('正文为空:不请求也不崩', (tester) async {
      var calls = 0;
      TranslateApi.clientFactory = () => MockClient((request) async {
        calls++;
        return _chat('<p>x</p>');
      });
      _enableAuto();

      await tester.pumpWidget(
        _wrap(const DescriptionCard(mod: _emptyMod, onLinkTap: _noop)),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(calls, 0);
    });
  });
}

/// 自动翻译用例的前置:配置好接口 Key 并打开开关
void _enableAuto() {
  AgentSettings.instance
    ..setApiKey('k')
    ..setBaseUrl('https://api.example.com/v1');
  LanguageSettings.instance.setAutoTranslate(true);
}

/// 推完自动翻译触发(post-frame 判定)与请求响应所需的帧
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

void _noop(String url) {}
