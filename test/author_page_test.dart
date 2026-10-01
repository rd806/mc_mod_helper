import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/page/detail/author_page.dart';
import 'package:mc_mod_helper/page/detail/project_page.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

/// 作者页真机抓下来的结构(截取头部 + 参与项目)
String _authorHtml() => '''
<html><head><title>水咬狸花猫 - 个人作者 - MC百科</title></head><body>
<div class="author-row">
  <div class="author-user-frame hascontent">
    <div class="author-user-avatar">
      <span><img alt="水咬狸花猫" src="//i.mcmod.cn/user/avatar/a.png" /></span>
    </div>
    <div class="author-name">
      <span class="name"><h5>水咬狸花猫</h5></span>
    </div>
  </div>
  <div class="author-content common-text font14">
    <div class="text"><p>哔哩哔哩同名，剑拔弩张之时整合包作者。</p></div>
  </div>
  <div class="author-mods"><div class="title">参与项目:</div>
    <div class="list"><ul>
      <div class="block">
        <div class="cover"><a href="/modpack/883.html" title="剑拔弩张之时">
          <img src="//i.mcmod.cn/modpack/cover/883.jpg" /></a></div>
        <div class="info"><div class="name">
          <a href="/modpack/883.html" title="剑拔弩张之时">剑拔弩张之时</a></div>
          <div class="position">所有者/美术</div></div>
      </div>
      <div class="block">
        <div class="cover"><a href="/class/459.html" title="JEI物品管理器 (Just Enough Items)">
          <img src="//i.mcmod.cn/class/cover/459.jpg" /></a></div>
        <div class="info"><div class="name">
          <a href="/class/459.html" title="JEI物品管理器 (Just Enough Items)">JEI物品管理器</a></div>
          <div class="position">贡献者</div></div>
      </div>
    </ul></div>
  </div>
</div>
</body></html>''';

/// 详情页(点作品卡片跳进去时用,只要标题能解析出来即可)
String _detailHtml() => '''
<html><head><title>剑拔弩张之时 - MC百科|最大的Minecraft中文MOD百科</title></head>
<body><li class="text-area common-text"><p>整合包正文。</p></li></body></html>''';

/// CurseForge 的作者作品:每页 20 条,总的 [total] 条做成分页
http.Response _cfPage(Uri uri, int total) {
  final index = int.tryParse(uri.queryParameters['index'] ?? '0') ?? 0;
  final count = (total - index).clamp(0, 20);
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'data': [
          for (var i = 0; i < count; i++)
            {
              'id': index + i,
              'name': '作品${index + i}',
              'summary': '简介',
              'classId': 6,
            },
        ],
        'pagination': {'totalCount': total},
      }),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// 推进请求(各 API 有 1 秒节流)与动画,不用 pumpAndSettle:
/// 有在飞的定时器时 pumpAndSettle 会提前返回
Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

Widget _page({
  String id = '32946',
  ModSource source = ModSource.mcmod,
  String? initialName,
  String? initialUrl,
}) => MaterialApp(
  home: AuthorPage(
    id: id,
    source: source,
    initialName: initialName,
    initialUrl: initialUrl,
  ),
);

void main() {
  setUpAll(() async {
    // 点作品卡片会进详情页:收藏按钮与浏览历史都要数据库
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_author_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
    await HistoryService.instance.init(dbPath: '${dir.path}/history.db');
  });

  setUp(() async {
    McmodApi.clearCaches();
    CurseforgeApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await DisplaySettings.instance.load();
  });

  testWidgets('作者页:名字/简介/作品数量,并提示已经到底', (tester) async {
    final uris = <Uri>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      return http.Response.bytes(utf8.encode(_authorHtml()), 200);
    });

    await tester.pumpWidget(_page(initialName: '水咬狸花猫'));
    await _settle(tester);

    expect(uris.single.path, '/author/32946.html');
    // 标题栏与头部各一份名字
    expect(find.text('水咬狸花猫'), findsWidgets);
    expect(find.textContaining('剑拔弩张之时整合包作者'), findsOneWidget);
    expect(find.text('作品 (2)'), findsOneWidget);
    expect(find.text('剑拔弩张之时'), findsOneWidget);
    expect(find.text('JEI物品管理器'), findsOneWidget);
    // 副标题(英文名)取自链接 title 属性的括号,卡片上显示在中文名下面
    expect(find.text('Just Enough Items'), findsOneWidget);
    // mcmod 作者页一次给全:没有下一页,尾部直接到底
    expect(find.text('已经到底啦'), findsOneWidget);
  });

  testWidgets('作者页:加载失败给重试,重试后出内容', (tester) async {
    var failed = false;
    McmodApi.clientFactory = () => MockClient((request) async {
      if (!failed) {
        failed = true;
        return http.Response('server error', 500);
      }
      return http.Response.bytes(utf8.encode(_authorHtml()), 200);
    });

    await tester.pumpWidget(_page());
    await _settle(tester);

    expect(find.textContaining('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await _settle(tester);

    expect(find.text('作品 (2)'), findsOneWidget);
    expect(find.text('剑拔弩张之时'), findsOneWidget);
  });

  testWidgets('作者页:没有作品时给空态', (tester) async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><body><div class="author-row">'
          '<div class="author-user-frame"><div class="author-user-avatar">'
          '<span><img src="//i.mcmod.cn/u/a.png"></span></div>'
          '<div class="author-name"><span class="name"><h5>新人作者</h5></span>'
          '</div></div></div></body></html>',
        ),
        200,
      ),
    );

    await tester.pumpWidget(_page(id: '1'));
    await _settle(tester);

    expect(find.text('新人作者'), findsWidgets);
    expect(find.text('作品 (0)'), findsOneWidget);
    expect(find.text('这里还没有他的作品'), findsOneWidget);
  });

  testWidgets('作者页:作品可分页,滚到底加载下一页', (tester) async {
    final uris = <Uri>[];
    CurseforgeApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      return _cfPage(request.url, 25);
    });

    await tester.pumpWidget(
      _page(id: '12345', source: ModSource.curseforge, initialName: '某作者'),
    );
    await _settle(tester);

    expect(uris.single.queryParameters['authorId'], '12345');
    expect(find.text('作品 (20)'), findsOneWidget);
    expect(find.text('作品0'), findsOneWidget);

    // 滚到底触发下一页(index 偏移制)
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    expect(uris.last.queryParameters['index'], '20');

    // 新一页接在旧内容后面,再滚到底才能看到它和到底提示
    // (顶部那块「作品 (n)」已经出屏,滚动视图外的 sliver 不会被 onstage 找到)
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);
    expect(find.text('作品24'), findsOneWidget);
    expect(find.text('已经到底啦'), findsOneWidget);
  });

  testWidgets('作者页:点作品卡片进详情页(类型跟着作品走)', (tester) async {
    final uris = <Uri>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      final html = request.url.path.startsWith('/author/')
          ? _authorHtml()
          : _detailHtml();
      return http.Response.bytes(utf8.encode(html), 200);
    });

    await tester.pumpWidget(_page());
    await _settle(tester);

    await tester.tap(find.text('剑拔弩张之时'));
    await _settle(tester, rounds: 4);

    expect(find.byType(ProjectPage), findsOneWidget);
    // 整合包作品要走 /modpack/,别按模组的 /class/ 取
    expect(uris.last.path, '/modpack/883.html');
    expect(find.textContaining('整合包正文'), findsOneWidget);
  });
}
