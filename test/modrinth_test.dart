import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/modrinth.dart';
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
      'body': '## 简介\n\n高性能渲染引擎。\n\n| 按键 | 功能 |\n| --- | --- |\n| F3 | 调试信息 |',
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
      expect(m.id, 0);
      expect(m.title, 'Sodium');
      expect(m.source, 'modrinth');
      expect(m.sourceId, 'sodium');
      expect(m.statsText, '下载 863万 · 关注 3200');
      expect(m.pageUrl, 'https://modrinth.com/mod/sodium');
    });

    test('getDetail 映射到 ModDetail(markdown 转换)', () async {
      final d = await ModrinthApi.getDetail('sodium');
      expect(d.title, 'Sodium');
      expect(d.source, 'modrinth');
      expect(d.sourceId, 'sodium');
      // 表格带边框与 collapse
      expect(d.description, contains('<table'));
      expect(d.description, contains('border-collapse'));
      expect(d.platform, 'Fabric');
      expect(d.environment, '仅客户端');
      expect(d.mcVersions, ['1.21.1']);
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
      final tech = cats.firstWhere((c) => c.sourceId == 'technology');
      expect(tech.source, 'modrinth');
      expect(tech.id, 0);
    });

    test('getCategoryMods 按 offset 分页并计算总页数', () async {
      final r1 = await ModrinthApi.getCategoryMods('technology');
      expect(r1.mods.first.sourceId, 'create');
      expect(r1.totalPages, 3); // 45 条 / 20 每页 = 3 页

      final r2 = await ModrinthApi.getCategoryMods('technology', page: 2);
      expect(r2.mods, hasLength(1));
      expect(r2.totalPages, 3);
    });
  });

  testWidgets('数据来源切到 Modrinth 后搜索与详情走 Modrinth', (tester) async {
    await SettingsService.instance.load();

    // 启动应用:主页两个请求(真实 HTTP 400)按既有节奏推完
    await tester.pumpWidget(const McModHelper());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // 切来源:主页分类随之重拉(Modrinth 分类,MockClient 立即返回)
    SettingsService.instance.setDataSource('modrinth');
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

    // 点结果进详情:ModrinthApi 距上次搜索不足 1s,有节流 Timer,显式推进
    await tester.tap(find.text('Sodium'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // 详情:标题(测量层+显示层可能出现两次)、版本芯片
    expect(find.text('Sodium'), findsWidgets);
    expect(find.text('1.21.1'), findsWidgets);
    await tester.pumpAndSettle(); // 收尾路由动画(此时无挂起 Timer)
    // 「模组介绍」在视口外(ListView 懒构建),向上拖动详情列表再断言
    // (fwfh 渲染的正文是 RichText,需要 findRichText)
    await tester.drag(find.byType(DetailPage), const Offset(0, -600));
    await tester.pump();
    expect(
      find.textContaining('高性能渲染引擎', findRichText: true),
      findsWidgets,
    );
  });
}
