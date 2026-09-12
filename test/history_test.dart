import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/model/mod/mod_summary.dart';
import 'package:mc_mod_helper/page/custom.dart';
import 'package:mc_mod_helper/page/custom/history.dart';
import 'package:mc_mod_helper/page/more/description.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ModSummary _mod(String id, {String? title}) => ModSummary(
  id: id,
  title: title ?? '模组$id',
  description: '第 $id 个模组',
  source: ModSource.mcmod,
);

/// Modrinth 详情页的三个接口
Future<http.Response> _modrinth(http.Request request) async {
  if (request.url.path == '/v2/project/jei') {
    return _json({
      'title': 'JEI',
      'body': '查看物品的合成配方',
      'icon_url': null,
      'game_versions': ['1.21.1'],
      'loaders': ['fabric'],
      'client_side': 'required',
      'server_side': 'unsupported',
    });
  }
  if (request.url.path == '/v2/project/jei/version') {
    return _json([
      {
        'loaders': ['fabric'],
        'game_versions': ['1.21.1'],
      },
    ]);
  }
  if (request.url.path == '/v2/project/jei/members') {
    return _json([
      {
        'user': {'username': 'mezz'},
        'role': 'Owner',
      },
    ]);
  }
  return http.Response('not found', 404);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    // 收藏服务:CustomPage 的入口计数要读它
    final favDir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_custom_test',
    );
    await FavoritesService.instance.init(dbPath: '${favDir.path}/favorites.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DisplaySettings.instance.load();
    // 每个用例一个全新的历史库:互不干扰
    dir = await Directory.systemTemp.createTemp('mcmodhelper_sqlite_history');
    await HistoryService.instance.init(dbPath: '${dir.path}/history.db');
    await HistoryService.instance.clear();
    await FavoritesService.instance.clear();
  });

  group('HistoryService', () {
    test('记录浏览:同一个模组只留一条,次数累加并置顶', () async {
      final service = HistoryService.instance;
      await service.record(_mod('1'));
      await service.record(_mod('2'));
      expect(service.list().map((h) => h.id), ['2', '1']);

      // 再看一次 1:不新增记录,次数 +1 并回到最前
      await service.record(_mod('1'));
      final list = service.list();
      expect(list.map((h) => h.id), ['1', '2']);
      expect(list.first.visits, 2);
      expect(list.last.visits, 1);
    });

    test('记录带着标题/简介等信息,可直接转成列表摘要', () async {
      final service = HistoryService.instance;
      await service.record(_mod('459', title: '[JEI] JEI物品管理器'));

      final entry = service.list().single;
      expect(entry.title, '[JEI] JEI物品管理器');
      expect(entry.description, '第 459 个模组');
      expect(entry.source, ModSource.mcmod);
      expect(entry.visits, 1);

      final summary = service.summaries().single;
      expect(summary.id, '459');
      expect(summary.title, '[JEI] JEI物品管理器');
      expect(summary.source, ModSource.mcmod);
    });

    test('按来源区分:不同来源的同一个 id 是两条记录', () async {
      final service = HistoryService.instance;
      await service.record(_mod('jei'));
      await service.record(
        const ModSummary(
          id: 'jei',
          title: 'JEI',
          description: '',
          source: ModSource.modrinth,
        ),
      );
      expect(service.list(), hasLength(2));
    });

    test('删除单条与清空', () async {
      final service = HistoryService.instance;
      await service.record(_mod('1'));
      await service.record(_mod('2'));

      await service.remove(_mod('1'));
      expect(service.list().map((h) => h.id), ['2']);
      // 未记录过的模组:无操作
      await service.remove(_mod('999'));
      expect(service.list(), hasLength(1));

      await service.clear();
      expect(service.list(), isEmpty);
    });

    test('重新打开数据库后记录还在(模拟重启)', () async {
      await HistoryService.instance.record(_mod('1'));
      await HistoryService.instance.record(_mod('2'));

      // 用同一个库文件重新初始化
      await HistoryService.instance.init(dbPath: '${dir.path}/history.db');
      expect(HistoryService.instance.list().map((h) => h.id), ['2', '1']);
    });

    test('超过上限时丢弃最旧的', () async {
      final service = HistoryService.instance;
      for (var i = 0; i < HistoryService.maxEntries + 5; i++) {
        await service.record(_mod('$i'));
      }
      final list = service.list();
      expect(list, hasLength(HistoryService.maxEntries));
      expect(list.first.id, '${HistoryService.maxEntries + 4}'); // 最新的
      expect(list.any((h) => h.id == '0'), isFalse); // 最旧的被丢弃
    });
  });

  testWidgets('历史页:空态 → 有条目 → 清空', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HistoryPage()));
    expect(find.textContaining('还没有浏览记录'), findsOneWidget);

    await HistoryService.instance.record(_mod('1', title: '模组甲'));
    await tester.pump();
    expect(find.textContaining('还没有浏览记录'), findsNothing);
    expect(find.text('模组甲'), findsOneWidget);

    // 清空:确认后回到空态
    await tester.tap(find.byTooltip('清空历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有浏览记录'), findsOneWidget);
    expect(HistoryService.instance.list(), isEmpty);
  });

  testWidgets('「我的」页:两个入口的计数与跳转', (tester) async {
    await FavoritesService.instance.add(
      Likes(id: '459', title: '模组甲', description: '', date: 1.0),
    );
    await HistoryService.instance.record(_mod('1', title: '模组甲'));

    await tester.pumpWidget(const MaterialApp(home: CustomPage()));
    await tester.pump();

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('1 个模组'), findsOneWidget);
    expect(find.text('浏览历史'), findsOneWidget);
    expect(find.text('1 条记录'), findsOneWidget);

    // 进入浏览历史页
    await tester.tap(find.text('浏览历史'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '浏览历史'), findsOneWidget);
    expect(find.text('模组甲'), findsOneWidget);
  });

  testWidgets('打开详情页会记一条浏览历史', (tester) async {
    ModrinthApi.clearCaches();
    ModrinthApi.clientFactory = () => MockClient(_modrinth);

    await tester.pumpWidget(
      const MaterialApp(
        home: DetailPage(
          id: 'jei',
          source: ModSource.modrinth,
          initialTitle: 'JEI',
        ),
      ),
    );
    // 三个接口各等 1s 节流
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    final list = HistoryService.instance.list();
    expect(list, hasLength(1));
    expect(list.single.id, 'jei');
    expect(list.single.title, 'JEI');
    expect(list.single.source, ModSource.modrinth);
  });
}
