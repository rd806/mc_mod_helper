import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/page/browse.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

/// 首页假 HTML:分类卡片(筛选栏的分类选项)
String _homeHtml() => '''
<html><body>
  <div class="class_category_block" data-id="1">
    <div class="icon"><a>科技</a></div>
    <div class="text"><span class="i">标语</span><span class="t">描述</span></div>
  </div>
  <div class="class_category_block" data-id="2">
    <div class="icon"><a>魔法</a></div>
    <div class="text"><span class="i">标语</span><span class="t">描述</span></div>
  </div>
</body></html>''';

/// modlist 页假 HTML:不带筛选参数时是版本选项,否则是模组列表
String _versionFilterHtml() => '''
<html><body>
  <div class="modlist-filter-block mcver">
    <ul>
      <li><a href="javascript:void(0);"
        onclick="window.location='/modlist.html?mcver=1.20.1'">1.20.1</a></li>
      <li><a href="javascript:void(0);"
        onclick="window.location='/modlist.html?mcver=1.7.10'">1.7.10</a></li>
    </ul>
  </div>
</body></html>''';

/// modlist 列表页假 HTML:每页 [count] 条 + 分页链接(总 [totalPages] 页)
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
      '<html><body>$blocks<div class="pagination">$pages</div></body></html>',
    ),
    200,
  );
}

/// 装好 mcmod 的假响应,并记录列表请求的 URL(筛选参数断言用)
List<Uri> installMcmod({int count = 20, int totalPages = 3}) {
  final listUris = <Uri>[];
  McmodApi.clientFactory = () => MockClient((request) async {
    if (request.url.path == '/') {
      return http.Response.bytes(utf8.encode(_homeHtml()), 200);
    }
    // 不带任何参数 = 版本选项;带参数 = 模组列表
    if (request.url.query.isEmpty) {
      return http.Response.bytes(utf8.encode(_versionFilterHtml()), 200);
    }
    listUris.add(request.url);
    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    return _modlist(page: page, count: count, totalPages: totalPages);
  });
  return listUris;
}

/// 推进 mcmod 的 1s 节流:筛选栏两个选项请求 + 列表第 1 页共三次
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

/// 展开筛选栏(摘要条右侧的箭头)
Future<void> expandFilter(WidgetTester tester) async {
  await tester.tap(find.byTooltip('展开筛选'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
    await DisplaySettings.instance.load();
  });

  testWidgets('首屏:按当前筛选拉第 1 页,不带多余参数', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    expect(uris, hasLength(1));
    expect(uris.single.queryParameters['sort'], ''); // 默认排序
    expect(uris.single.queryParameters.containsKey('category'), isFalse);
    expect(uris.single.queryParameters.containsKey('mcver'), isFalse);
    expect(find.text('模组1'), findsOneWidget);
    // 摘要条显示当前条件
    expect(find.text('全部分类 · 全部版本 · 默认排序'), findsOneWidget);
  });

  testWidgets('滚到底自动加载下一页,到底后提示且不再请求', (tester) async {
    final uris = installMcmod(totalPages: 2);
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    expect(uris, hasLength(1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 节流 → 第 2 页发出
    await tester.pump();
    expect(uris.map((u) => u.queryParameters['page'] ?? '1'), ['1', '2']);

    // 第二页内容在尾部:到底提示出现,不再请求第 3 页
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    expect(find.text('模组40'), findsOneWidget);
    expect(find.text('已经到底啦'), findsOneWidget);
    expect(uris, hasLength(2));
  });

  testWidgets('连续滚动翻页:第 2 页正常落地,尾部不卡在加载中', (tester) async {
    final uris = installMcmod(totalPages: 2);
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    expect(uris, hasLength(1));

    // 手指连续拖动:每小步都会触发一次滚动监听,而此刻第 2 页请求正排在
    // 站点 1s 节流之后(进行中)。真机就是这么滑的;
    // tester.drag 一步到底只会触发一次监听,盖不到「请求在飞时又来一次」的场景
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    await tester.pump(const Duration(seconds: 1)); // 节流 → 第 2 页发出
    await tester.pump();

    // 尾部不能卡在「加载中」:请求在飞时被自己的空调用挤掉序号时,
    // 响应会被丢弃且 _loading 永远收不回 false,就是卡在这里
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(uris.map((u) => u.queryParameters['page'] ?? '1'), ['1', '2']);
    expect(find.text('模组21'), findsOneWidget); // 第 2 页内容落地
  });

  testWidgets('展开筛选栏选分类:重拉第 1 页并带上分类参数', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    await expandFilter(tester);
    expect(find.widgetWithText(ChoiceChip, '科技'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(); // 先只更新选中态
    expect(uris, hasLength(1)); // 还没请求(防抖中)

    await tester.pump(const Duration(milliseconds: 350)); // 防抖到点 → 请求
    await tester.pump(const Duration(seconds: 1)); // 节流
    await tester.pump();
    expect(uris.last.queryParameters['category'], '1');
    expect(find.text('科技 · 全部版本 · 默认排序'), findsOneWidget);
  });

  testWidgets('连点两个筛选条件只发一次请求(防抖)', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    await expandFilter(tester);

    // 先点分类,紧接着点版本:只应发出最后一次(两者都带上)
    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(ChoiceChip, '1.20.1'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(uris, hasLength(2)); // 首屏 1 次 + 筛选后 1 次
    expect(uris.last.queryParameters['category'], '1');
    expect(uris.last.queryParameters['mcver'], '1.20.1');
  });

  testWidgets('分类 + 版本 + 排序三个条件同时生效', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    await expandFilter(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.widgetWithText(ChoiceChip, '1.20.1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.widgetWithText(ChoiceChip, '最新编辑'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final params = uris.last.queryParameters;
    expect(params['category'], '1');
    expect(params['mcver'], '1.20.1');
    expect(params['sort'], 'lastedittime');
    // 摘要条把三项都显示出来(显示的就是生效的)
    expect(find.text('科技 · 1.20.1 · 最新编辑'), findsOneWidget);
  });

  testWidgets('排序三档映射到站点的 sort 参数', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    for (final (label, sort) in [
      ('最新收录', 'createtime'),
      ('最新编辑', 'lastedittime'),
    ]) {
      await expandFilter(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(uris.last.queryParameters['sort'], sort, reason: label);
      // 收起面板,下一轮重新展开
      await tester.tap(find.byTooltip('收起筛选'));
      await tester.pumpAndSettle();
    }

    // 切回默认排序:条件与首屏那次完全相同 → 命中会话缓存,不再请求,
    // 界面直接回到那份结果(站点有 1s 节流,能复用就别再排一次队)
    await expandFilter(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '默认排序'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(uris, hasLength(3)); // 首屏 + 两个排序
    expect(find.text('全部分类 · 全部版本 · 默认排序'), findsOneWidget);
    expect(find.text('模组1'), findsOneWidget);
  });

  testWidgets('展开/收起筛选栏本身不触发请求', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    expect(uris, hasLength(1));

    await expandFilter(tester);
    expect(find.text('排序'), findsOneWidget);
    await tester.tap(find.byTooltip('收起筛选'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(uris, hasLength(1)); // 仍然只有首屏那一次
  });

  testWidgets('重置筛选:回到无分类无版本、默认排序', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    await expandFilter(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(uris.last.queryParameters['category'], '1');

    // 重置后与首屏的条件相同 → 会话缓存命中(不再请求),界面立刻回到无筛选
    await tester.tap(find.text('重置'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(uris, hasLength(2)); // 首屏 + 带分类那次
    expect(find.text('全部分类 · 全部版本 · 默认排序'), findsOneWidget);
    expect(find.text('模组1'), findsOneWidget); // 回到未筛选的那份结果
  });

  testWidgets('首屏加载失败:给出重试', (tester) async {
    McmodApi.clientFactory = () =>
        MockClient((request) async => http.Response('boom', 500));
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    expect(find.textContaining('加载失败'), findsWidgets);
    expect(find.text('重试'), findsWidgets);
  });

  testWidgets('没有符合条件的模组:显示空态', (tester) async {
    installMcmod(count: 0);
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    expect(find.text('没有符合条件的模组'), findsOneWidget);
  });

  testWidgets('切换数据来源:筛选栏换一批选项并重拉列表', (tester) async {
    final modrinthUris = <Uri>[];
    // Modrinth:分类 / 版本 / 搜索三条路由
    ModrinthApi.clientFactory = () => MockClient((request) async {
      if (request.url.path == '/v2/tag/category') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'name': 'technology',
                'project_type': 'mod',
                'header': 'categories',
              },
            ]),
          ),
          200,
        );
      }
      if (request.url.path == '/v2/tag/game_version') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {'version': '1.21.1', 'version_type': 'release'},
            ]),
          ),
          200,
        );
      }
      modrinthUris.add(request.url);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'hits': [
              {
                'slug': 'create',
                'title': 'Create',
                'description': 'Tech mod',
                'icon_url': null,
                'downloads': 1,
                'follows': 1,
              },
            ],
            'total_hits': 1,
          }),
        ),
        200,
      );
    });

    final mcmodUris = installMcmod();
    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);
    await expandFilter(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(mcmodUris.last.queryParameters['category'], '1');

    // 换来源:分类/版本体系完全不同,必须清掉并重拉
    ModrinthApi.clearCaches();
    DisplaySettings.instance.setDataSource(ModSource.modrinth);
    await settle(tester, rounds: 6);

    expect(find.text('全部分类 · 全部版本 · 默认排序'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(modrinthUris, isNotEmpty);
    expect(modrinthUris.last.queryParameters.containsKey('facets'), isTrue);
  });

  testWidgets('类型标签:切到整合包走 modpack.html,并清掉已选的分类/版本', (tester) async {
    final listUris = <Uri>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path == '/') {
        return http.Response.bytes(utf8.encode(_homeHtml()), 200);
      }
      // 选项请求不带筛选参数(模组在 modlist.html、整合包在 modpack.html);
      // 带参数的是列表请求,记录下来供断言
      if (request.url.query.isEmpty) {
        return http.Response.bytes(utf8.encode(_versionFilterHtml()), 200);
      }
      listUris.add(request.url);
      final isPack = path == '/modpack.html';
      return http.Response.bytes(
        utf8.encode(
          '<html><body>'
          '<div class="modlist-block"><div class="title">'
          '<p class="name"><a href="/${isPack ? 'modpack' : 'class'}/1.html">'
          '${isPack ? '整合包' : '模组'}1</a></p></div></div>'
          '<div class="pagination"><a data-page="1" href="?page=1">1</a></div>'
          '</body></html>',
        ),
        200,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: BrowsePage()));
    await settle(tester);

    // 顶部两个类型标签,默认在模组
    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.text('模组'), findsOneWidget);
    expect(find.text('整合包'), findsOneWidget);
    expect(listUris.single.path, '/modlist.html');

    // 先选一个分类,切类型后应当被清掉
    await expandFilter(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '科技'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(listUris.last.queryParameters['category'], '1');

    // 切到整合包:按 modpack.html 重拉,分类回到「全部分类」
    await tester.tap(find.text('整合包'));
    await settle(tester, rounds: 6);
    expect(listUris.last.path, '/modpack.html');
    expect(listUris.last.queryParameters.containsKey('category'), isFalse);
    expect(find.text('全部分类 · 全部版本 · 默认排序'), findsOneWidget);
    expect(find.text('整合包1'), findsOneWidget); // 整合包列表渲染出来了
  });

  testWidgets('详情页版本胶囊:预设版本的浏览页直接按该版本筛选', (tester) async {
    final uris = installMcmod();
    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(
          initialFilter: const Filter(
            type: ProjectType.mod,
            modSource: ModSource.mcmod,
            sortMethod: SortMethod.none,
            version: ProjectVersion(version: '1.20.1', source: ModSource.mcmod),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(uris.last.queryParameters['mcver'], '1.20.1');
    expect(find.text('全部分类 · 1.20.1 · 默认排序'), findsOneWidget);
  });
}
