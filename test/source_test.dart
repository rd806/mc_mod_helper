import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/value/source.dart';

/// JSON 响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// mcmod 搜索页 HTML(单个结果条目,结构与 modlist 页的 _parseModlist 一致)
String _mcmodHtml() => '''
<html><body>
  <div class="modlist-block">
    <div class="title">
      <p class="name"><a href="/class/459.html">[JEI] JEI物品管理器</a></p>
      <p class="ename"><a href="/class/459.html">Just Enough Items</a></p>
    </div>
    <div class="cover"><img src="//i.mcmod.cn/jei.png"></div>
    <div class="intro-content"><span>查看物品的合成与用途</span></div>
  </div>
</body></html>''';

/// 1x1 透明 PNG(验证码挑战页需要真实可解码的图片)
const String _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  setUp(() {
    McmodApi.clearCaches();
    ModrinthApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
  });

  test('getTotalSearch 并发聚合各来源,单个来源失败不影响其它', () async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(utf8.encode(_mcmodHtml()), 200),
    );
    ModrinthApi.clientFactory = () =>
        MockClient((request) async => http.Response('server error', 500));

    final total = await SourceManager.getTotalSearch([
      ModSource.mcmod,
      ModSource.modrinth,
    ], 'jei');
    expect(total.results.keys, [ModSource.mcmod]);
    expect(total.results[ModSource.mcmod]!.single.id, '459');
    expect(total.results[ModSource.mcmod]!.single.title, '[JEI] JEI物品管理器');
    expect(total.results[ModSource.mcmod]!.single.subName, 'Just Enough Items');
    // 失败的来源:错误按来源记录,不吞掉整个搜索
    expect(total.errors.keys, [ModSource.modrinth]);
    expect(total.errors[ModSource.modrinth], contains('HTTP 500'));
  });

  test('getTotalSearch 全部来源成功时 results 全收录,errors 为空', () async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(utf8.encode(_mcmodHtml()), 200),
    );
    ModrinthApi.clientFactory = () => MockClient(
      (request) async => _json({
        'hits': [
          {
            'slug': 'jei',
            'title': 'JEI',
            'description': '',
            'icon_url': null,
            'downloads': 100,
            'follows': 10,
          },
        ],
        'total_hits': 1,
      }),
    );

    final total = await SourceManager.getTotalSearch([
      ModSource.mcmod,
      ModSource.modrinth,
    ], 'jei');
    expect(
      total.results.keys,
      containsAll([ModSource.mcmod, ModSource.modrinth]),
    );
    expect(total.results[ModSource.modrinth]!.single.id, 'jei');
    expect(total.errors, isEmpty);
  });

  test('getTotalSearch:mcmod 验证码异常直接上抛(由页面弹窗处理)', () async {
    // 与 mcmod_captcha_test 相同的最小挑战页结构
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><body><form method="POST" id="captchaForm">'
          '<img id="captchaImage" src="data:image/png;base64,$_tinyPng">'
          '<p class="captcha-question">图中有多少个青金石?</p>'
          '</form></body></html>',
        ),
        403,
      ),
    );

    expect(
      () => SourceManager.getTotalSearch([ModSource.mcmod], 'jei'),
      throwsA(isA<McmodCaptchaException>()),
    );
  });
}
