import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/service/agent/translate.dart';
import 'package:mc_mod_helper/model/mod/mod_detail.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/settings.dart';
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

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() async {
    TranslateApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
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
}

void _noop(String url) {}
