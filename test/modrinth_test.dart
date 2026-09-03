import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/api/source.dart';
import 'package:mc_mod_helper/main.dart';
import 'package:mc_mod_helper/page/detail.dart';
import 'package:mc_mod_helper/service/settings.dart';

/// JSON 响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _json(Object data) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 搜索 + 详情两条路由的假响应
Future<http.Response> _handler(http.Request request) async {
  if (request.url.path == '/v2/tag/category') {
    return _json([
      {'icon': '', 'name': 'technology', 'project_type': 'mod', 'header': 'categories'},
      {'icon': '', 'name': 'magic', 'project_type': 'mod', 'header': 'categories'},
      {'icon': '', 'name': '128x', 'project_type': 'resourcepack', 'header': 'resolutions'},
    ]);
  }
  if (request.url.path == '/v2/search') {
    final facets = request.url.queryParameters['facets'] ?? '';
    if (facets.contains('categories:technology')) {
      return _json({
        'hits': [
          {
            'slug': 'create',
            'title': 'Create',
            'description': 'Tech mod',
            'icon_url': null,
            'downloads': 100000,
            'follows': 500,
          },
        ],
        'total_hits': 45,
      });
    }
    return _json({
      'hits': [
        {
          'slug': 'sodium',
          'title': 'Sodium',
          'description': 'A modern rendering engine',
          'icon_url': 'https://cdn.modrinth.com/data/sodium.png',
          'downloads': 8630000,
          'follows': 3200,
        },
      ],
      'total_hits': 1,
    });
  }
  if (request.url.path == '/v2/project/sodium') {
    return _json({
      'title': 'Sodium',
      'body': '## 简介\n\n高性能渲染引擎。\n\n<div style="color:red">原始HTML</div>\n\n'
          '| 按键 | 功能 |\n| --- | --- |\n| F3 | 调试信息 |',
      'icon_url': 'https://cdn.modrinth.com/data/sodium_icon.png',
      'game_versions': ['1.21.1'],
      'loaders': ['fabric'],
      'client_side': 'required',
      'server_side': 'unsupported',
      'source_url': 'https://github.com/CaffeineMC/sodium',
      'issues_url': 'https://github.com/CaffeineMC/sodium/issues',
      'wiki_url': null,
      'discord_url': 'https://discord.gg/sodium',
      'donation_urls': [],
    });
  }
  if (request.url.path == '/v2/project/sodium/version') {
    // 版本列表:条目带 loaders[] 与 game_versions[],按加载器聚合
    return _json([
      {'loaders': ['fabric'], 'game_versions': ['1.21.1', '1.20.4']},
      {'loaders': ['forge'], 'game_versions': ['1.20.4']},
    ]);
  }
  return http.Response('not found', 404);
}

void main() {
  setUp(() {
    ModrinthApi.clearCaches();
    ModrinthApi.clientFactory = () => MockClient(_handler);
    SharedPreferences.setMockInitialValues({});
  });

  group('ModrinthApi 解析', () {
    test('search 映射到 ModSummary', () async {
      final results = await ModrinthApi.search('sodium');
      expect(results, hasLength(1));
      final m = results.first;
      expect(m.id, 'sodium');
      expect(m.title, 'Sodium');
      expect(m.source, ModSource.modrinth);
      expect(m.statsText, '下载 863万 · 关注 3200');
      expect(m.pageUrl, 'https://modrinth.com/mod/sodium');
    });

    test('getDetail 映射到 ModDetail(Markdown 转 HTML,原生 HTML 透传)', () async {
      final d = await ModrinthApi.getDetail('sodium');
      expect(d.id, 'sodium');
      expect(d.title, 'Sodium');
      expect(d.source, ModSource.modrinth);
      // Markdown 转成 HTML:标题/表格是 HTML 标签,
      // 原生 HTML 块(<div style=...>)原样透传
      expect(d.description, contains('<h2'));
      expect(d.description, contains('<table>'));
      expect(d.description, contains('<div style="color:red">原始HTML</div>'));
      expect(d.platform, 'Fabric');
      // 环境为 [客户端, 服务端] 枚举值列表(client_side=required,
      // server_side=unsupported → 仅客户端)
      expect(d.environment, ['required', 'unsupported']);
      // 版本按加载器分组(版本列表接口聚合,去重保序)
      expect(d.mcVersions, {
        'fabric': ['1.21.1', '1.20.4'],
        'forge': ['1.20.4'],
      });
      expect(d.links.map((l) => l.name), contains('GitHub'));
      expect(d.links.map((l) => l.name), contains('Discord'));
      expect(d.pageUrl, 'https://modrinth.com/mod/sodium');
    });

    test('非 200 抛出含状态码的异常', () async {
      ModrinthApi.clientFactory = () =>
          MockClient((request) async => http.Response('', 404));
      expect(
        () => ModrinthApi.search('none'),
        throwsA(predicate((e) => e.toString().contains('HTTP 404'))),
      );
    });

    test('getCategories 只保留 mod 分类并映射中文名', () async {
      final cats = await ModrinthApi.getCategories();
      expect(cats.map((c) => c.name), containsAll(['科技', '魔法']));
      expect(cats.map((c) => c.name), isNot(contains('128x')));
      final tech = cats.firstWhere((c) => c.id == 'technology');
      expect(tech.source, ModSource.modrinth);
      expect(tech.id, 'technology');
    });

    test('getCategoryMods 按 offset 分页并计算总页数', () async {
      final r1 = await ModrinthApi.getCategoryMods('technology');
      expect(r1.mods.first.id, 'create');
      expect(r1.totalPages, 3); // 45 条 / 20 每页 = 3 页

      final r2 = await ModrinthApi.getCategoryMods('technology', page: 2);
      expect(r2.mods, hasLength(1));
      expect(r2.totalPages, 3);
    });
  });

  testWidgets('数据来源切到 Modrinth 后搜索与详情走 Modrinth', (tester) async {
    await SettingsService.instance.load();
    // 本用例验证 hyper_render 渲染路径,显式指定渲染方法
    // (默认 'default' 是 HtmlContent,详情页不会出现 HyperViewer)
    SettingsService.instance.setRenderType('hyperViewer');

    // 启动应用:主页两个请求(真实 HTTP 400)按既有节奏推完
    await tester.pumpWidget(const McModHelper());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // 切来源:主页分类随之重拉(Modrinth 分类,MockClient 立即返回)
    SettingsService.instance.setDataSource(ModSource.modrinth);
    await tester.pumpAndSettle();
    expect(find.text('科技'), findsWidgets); // Modrinth 分类卡片已渲染

    // 进搜索页
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // 搜索:主页分类请求已占用节流时间戳,搜索请求需等约 1s 节流计时器
    await tester.enterText(find.byType(TextField), 'sodium');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('A modern rendering engine'), findsOneWidget);

    // 点结果进详情:详情要发两个请求(项目详情 + 版本列表),每个都受
    // 1s 节流且与上次搜索有间隔,显式推进两轮节流计时器
    await tester.tap(find.text('Sodium'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 节流 → 项目详情请求发出
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 节流 → 版本列表请求发出
    await tester.pump();
    await tester.pump();

    // 详情:标题(测量层+显示层可能出现两次)
    expect(find.text('Sodium'), findsWidgets);
    await tester.pumpAndSettle();
    // 宽屏右栏顺序:加载环境 → 相关链接 → 支持版本;环境区块把版本区
    // 顶到视口外(ListView 懒构建不渲染),把右栏 ListView 往上拖再断言。
    // 右栏 = DetailPage 下第二个 ListView(左栏是第一个)
    final rightList = find
        .descendant(of: find.byType(DetailPage), matching: find.byType(ListView))
        .at(1);
    await tester.drag(rightList, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('1.21.1', findRichText: true), findsWidgets);
    // 「模组介绍」在左栏(宽屏)或下方(窄屏),向上拖动详情列表再断言。
    // hyper_render 在单个 RenderObject 里自绘文本,不能用 find.text 找,
    // 改为校验转换后的 HTML 已正确传入 HyperViewer
    await tester.drag(find.byType(DetailPage), const Offset(0, -600));
    await tester.pump();
    final viewer = tester.widget<HyperViewer>(find.byType(HyperViewer));
    expect(viewer.content, contains('高性能渲染引擎'));
    expect(viewer.content, contains('<table>'));
    // 描述内容包了开启鼠标拖拽的 ScrollConfiguration
    // (桌面端默认行为不含鼠标,表格横向滚动容器会拖不动)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is ScrollConfiguration &&
            w.behavior.dragDevices.contains(PointerDeviceKind.mouse),
      ),
      findsWidgets,
    );
  });
}
