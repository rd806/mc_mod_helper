import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/page/more/description.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/setting/settings.dart';

http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 详情页三个接口的假响应
Future<http.Response> _handler(http.Request request) async {
  if (request.url.path == '/v2/project/jei') {
    return _json({
      'title': 'JEI',
      'body':
          'Just Enough Items\n\n${List.filled(40, '这是一段用于撑高介绍页正文字节的内容,'
          '方便验证正文滚动与返回顶部按钮。').join('\n\n')}',
      'icon_url': null,
      'downloads': 1000000,
      'followers': 5000,
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
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_narrow_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
  });

  setUp(() async {
    ModrinthApi.clearCaches();
    ModrinthApi.clientFactory = () => MockClient(_handler);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  testWidgets('窄屏详情:封面+吸顶按钮+两页签各自独立滚动', (tester) async {
    // 窄屏手机尺寸(宽 < 800 → 走 _buildNarrowPage)
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // 加载完成:介绍页可见,吸顶按钮两个分段都在
    expect(find.text('JEI', findRichText: true), findsWidgets);
    expect(find.text('介绍'), findsOneWidget);
    expect(find.text('信息'), findsOneWidget);
    // 封面/吸顶按钮/正文同处一个 CustomScrollView
    expect(find.byType(CustomScrollView), findsWidgets);

    // 介绍页正文可见(与封面同流滚动)
    expect(
      find.textContaining('Just Enough Items', findRichText: true),
      findsWidgets,
    );

    // 向上滚一段:封面滚出、按钮吸顶,滚动协调无异常
    // (同流语义:位移先耗在滚封面,封面滚完才进入正文)
    await tester.drag(
      find.textContaining('Just Enough Items', findRichText: true),
      const Offset(0, -600),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 吸顶按钮仍在视口内(未随封面一起滚出)
    expect(find.text('介绍'), findsOneWidget);

    // 按钮 child 常驻,显隐看它外层 AnimatedOpacity 的透明度(淡入淡出)
    double arrowOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byIcon(Icons.arrow_upward),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    // 方向显隐:往上滚(offset 增大,向内容尾部)→ 淡出隐藏
    expect(arrowOpacity(), 0);

    // 往回滚一点(offset 减小,回顶部方向)→ 淡入显示
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 300),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(arrowOpacity(), 1);

    // 点击按钮回到整页顶部,随后淡出隐藏
    await tester.tap(find.byIcon(Icons.arrow_upward));
    // 回顶动画时长由组件默认 1s,给足帧数
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final pagePos = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(pagePos.position.pixels, lessThanOrEqualTo(1));
    expect(arrowOpacity(), 0);

    // 切到「信息」:正文替换为信息区块,无异常
    await tester.tap(find.text('信息'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('加载环境'), findsOneWidget);
    expect(find.textContaining('客户端：必需', findRichText: true), findsOneWidget);

    // 切回「介绍」正常
    await tester.tap(find.text('介绍'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Just Enough Items', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('桌面端宽窄切换:返回按钮随布局重绑 controller 不报错且可用', (tester) async {
    // 先以窄屏加载详情
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: DetailPage(
          id: 'jei',
          source: ModSource.modrinth,
          initialTitle: 'JEI',
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    double arrowOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byIcon(Icons.arrow_upward),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    // 切到宽屏(桌面)布局:按钮应改绑左栏 ListView
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 宽屏左栏是第一个 ListView(介绍);往下滚到底再回拉一小段,
    // 验证按钮已绑上新 controller 并随方向显示
    final leftList = find
        .descendant(
          of: find.byType(DetailPage),
          matching: find.byType(ListView),
        )
        .first;
    await tester.drag(leftList, const Offset(0, -800));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.drag(leftList, const Offset(0, 250));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(arrowOpacity(), 1);

    // 切回窄屏:再次重绑到整页 controller,无异常
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 上滚后(向底部)隐藏;回拉一小段应显示,证明窄屏 controller 也重绑生效
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 200),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(arrowOpacity(), 1);
    // 全程无 'attached to more than one' 之类的绑定异常(测试自行断言异常即红)
  });
}
