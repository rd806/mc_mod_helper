import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/service/agent/translate.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';

/// OpenAI 兼容 chat/completions 的假响应
http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 包一层 choices/message/content
http.Response _chat(String content) => _json({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
});

void main() {
  setUp(() async {
    TranslateApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await LanguageSettings.instance.load();
    await AgentSettings.instance.load();
    // 默认给一个可用的配置,测试里按需覆盖
    AgentSettings.instance
      ..setApiKey('test-key')
      ..setBaseUrl('https://api.example.com/v1')
      ..setModel('test-model');
  });

  test('翻译请求:携带 Bearer Key 与模型,/chat/completions 路径正确', () async {
    final requests = <http.Request>[];
    TranslateApi.clientFactory = () => MockClient((request) async {
      requests.add(request);
      return _chat('<p>译好的内容</p>');
    });

    final out = await TranslateApi.translateHtml(
      '<p>original</p>',
      cacheKey: 'mcmod:1',
    );
    expect(out, '<p>译好的内容</p>');
    expect(requests, hasLength(1));
    final req = requests.single;
    expect(req.url.toString(), 'https://api.example.com/v1/chat/completions');
    expect(req.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['model'], 'test-model');
    // 提示词里带上原文与"保留 HTML 结构"要求
    final content = (body['messages'] as List).first as Map<String, dynamic>;
    expect(content['content'], contains('<p>original</p>'));
    expect(content['content'], contains('HTML'));
  });

  test('结果缓存:同一模组再次翻译不再发请求', () async {
    var calls = 0;
    // 单个 handler:按提示词里的目标语言返回不同译文
    // (翻译 API 惰性缓存 client,中途换 factory 不生效)
    TranslateApi.clientFactory = () => MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final prompt =
          ((body['messages'] as List).first as Map)['content'] as String;
      return _chat(prompt.contains('英语') ? '<p>english</p>' : '<p>译文</p>');
    });

    final a = await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'mcmod:1');
    final b = await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'mcmod:1');
    expect(a, b);
    expect(calls, 1);
    // cachedHtml 同步可读(详情卡片切换原文/译文用)
    expect(TranslateApi.cachedHtml('mcmod:1'), '<p>译文</p>');

    // 不同模组:单独请求;不同语言:单独缓存
    await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'mcmod:2');
    expect(calls, 2);
    await TranslateApi.translateHtml(
      '<p>x</p>',
      cacheKey: 'mcmod:1',
      targetLang: 'en',
    );
    expect(calls, 3);
    expect(
      TranslateApi.cachedHtml('mcmod:1', targetLang: 'en'),
      '<p>english</p>',
    );
  });

  test('清理 markdown 代码围栏', () async {
    TranslateApi.clientFactory = () =>
        MockClient((request) async => _chat('```html\n<p>围栏内</p>\n```'));
    final out = await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k');
    expect(out, '<p>围栏内</p>');
  });

  test('未配置 Key:抛引导异常且不发请求', () async {
    AgentSettings.instance.setApiKey('');
    var called = false;
    TranslateApi.clientFactory = () => MockClient((request) async {
      called = true;
      return _chat('x');
    });

    await expectLater(
      TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k'),
      throwsA(isA<TranslateNotConfiguredException>()),
    );
    expect(called, isFalse);
  });

  test('非 200:抛含状态码的异常', () async {
    TranslateApi.clientFactory = () =>
        MockClient((request) async => http.Response('bad key', 401));
    await expectLater(
      TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k'),
      throwsA(predicate((e) => e.toString().contains('HTTP 401'))),
    );
  });

  test('响应缺少内容:抛异常', () async {
    TranslateApi.clientFactory = () => MockClient(
      (request) async => _json({
        'choices': [
          {
            'message': {'role': 'assistant'},
          },
        ],
      }),
    );
    await expectLater(
      TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k'),
      throwsA(predicate((e) => e.toString().contains('翻译结果为空'))),
    );
  });

  test('思考模型兼容:请求体不带 temperature,并带上输出上限', () async {
    Map<String, dynamic>? sent;
    TranslateApi.clientFactory = () => MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _chat('<p>ok</p>');
    });
    await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k');
    // 部分思考模型兼容层会拒绝 temperature;max_tokens 给足避免正文被思维链挤掉
    expect(sent!.containsKey('temperature'), isFalse);
    expect(sent!['stream'], false);
    expect(sent!['max_tokens'], TranslateApi.maxOutputTokens);
  });

  test('思考模型兼容:content 为内容块数组时拼接文本', () async {
    TranslateApi.clientFactory = () => MockClient(
      (request) async => _json({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'reasoning_content': '先分析……',
              'content': [
                {'type': 'text', 'text': '<p>块一</p>'},
                {'type': 'text', 'text': '<p>块二</p>'},
              ],
            },
          },
        ],
      }),
    );
    final out = await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k');
    expect(out, '<p>块一</p><p>块二</p>');
  });

  test('思考模型兼容:只有 reasoning_content 时给出明确提示', () async {
    TranslateApi.clientFactory = () => MockClient(
      (request) async => _json({
        'choices': [
          {
            'message': {'role': 'assistant', 'reasoning_content': '思考中……'},
          },
        ],
      }),
    );
    await expectLater(
      TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k'),
      throwsA(predicate((e) => e.toString().contains('只返回了思考过程'))),
    );
  });

  test('思考模型兼容:finish_reason=length 提示被截断', () async {
    TranslateApi.clientFactory = () => MockClient(
      (request) async => _json({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '<p>半截'},
            'finish_reason': 'length',
          },
        ],
      }),
    );
    await expectLater(
      TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k'),
      throwsA(predicate((e) => e.toString().contains('截断'))),
    );
  });

  test('网关信封 {data:{...}} 与旧 completions 风格均可解析', () async {
    TranslateApi.clientFactory = () => MockClient(
      (request) async => _json({
        'data': {
          'choices': [
            {'text': '<p>旧风格</p>'},
          ],
        },
      }),
    );
    final out = await TranslateApi.translateHtml('<p>x</p>', cacheKey: 'k');
    expect(out, '<p>旧风格</p>');
  });

  test('长正文分块翻译并拼接(不截断内容)', () async {
    // 120 个段落,总长远超单块预算
    final long = List.generate(
      120,
      (i) => '<p>第$i段 English text ${'x' * 80}</p>',
    ).join();
    final prompts = <String>[];
    final progress = <String>[];
    TranslateApi.clientFactory = () => MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      prompts.add((body['messages'] as List).first['content'] as String);
      return _chat('<p>译文</p>');
    });

    final out = await TranslateApi.translateHtml(
      long,
      cacheKey: 'k',
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    // 拆成了多块,每块的 HTML 部分不超过预算(prompt 前缀另有 ~200 字符)
    expect(prompts.length, greaterThan(1));
    for (final p in prompts) {
      final htmlPart = p.substring(p.indexOf('HTML:\n') + 6);
      expect(htmlPart.length, lessThanOrEqualTo(TranslateApi.chunkChars));
      // 块边界没有切断标签:<p> 与 </p> 数量一致
      final opens = RegExp('<p>').allMatches(htmlPart).length;
      final closes = RegExp('</p>').allMatches(htmlPart).length;
      expect(opens, closes);
    }
    // 拼接结果 = 每块译文顺序相连
    expect(out, '<p>译文</p>' * prompts.length);
    // 进度回调完整(done 从 1 到 total)
    expect(progress.first, '1/${prompts.length}');
    expect(progress.last, '${prompts.length}/${prompts.length}');
  });

  test('单个超预算的大表格整体成块,不被切开', () async {
    // 一个超过预算的表格节点:整体作为一个请求,标签保持成对
    final bigTable = '<table><tr><td>${'长内容' * 4000}</td></tr></table>';
    final prompts = <String>[];
    TranslateApi.clientFactory = () => MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      prompts.add((body['messages'] as List).first['content'] as String);
      return _chat('<table><tr><td>已译</td></tr></table>');
    });

    await TranslateApi.translateHtml(bigTable, cacheKey: 'k2');
    expect(prompts, hasLength(1));
    final htmlPart = prompts.single.substring(
      prompts.single.indexOf('HTML:\n') + 6,
    );
    expect(htmlPart, contains('<table>'));
    expect(htmlPart, contains('</table>'));
  });
}
