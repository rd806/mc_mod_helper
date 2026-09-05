import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/api/modrinth.dart';
import 'package:mc_mod_helper/main.dart';
import 'package:mc_mod_helper/service/savings.dart';
import 'package:mc_mod_helper/service/settings.dart';
import 'package:mc_mod_helper/value/display.dart';
import 'package:mc_mod_helper/value/source.dart';

/// 启动应用并推进到两个页签(推荐/分类)都完成失败渲染。
///
/// 测试环境中网络请求被禁用(返回 HTTP 400)。四个页面挂在 IndexedStack
/// 中同时挂载,推荐页与分类页的两个请求共用 www 节流:推荐立即发出,
/// 分类挂起在约 1 秒的间隔计时器上;pumpAndSettle 会提前退出
/// 留下 pending Timer,因此这里显式推进假时钟。
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const McModHelper());
  await tester.pump(); // 推荐请求 400 → setState
  await tester.pump(const Duration(seconds: 1)); // 间隔计时器触发 → 分类请求发出
  await tester.pump(); // 分类 400 → setState
  await tester.pump(); // 渲染最终错误态
}

void main() {
  setUpAll(() async {
    // 收藏页挂在 IndexedStack 里随应用一起构建,ModTile 也带收藏按钮,
    // 因此整套应用级用例都要先初始化收藏数据库(生产环境由 main() 完成)
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
  });

  setUp(() async {
    // 单例跨用例共享:重置 mock 存储并 load,
    // load 对缺失键显式赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    // 重置各 Api 的节流时间戳与缓存:否则上个用例残留的请求时间
    // 会让"第一个请求立即发出"的节流节奏不可预测
    McmodApi.clearCaches();
    ModrinthApi.clearCaches();
  });

  testWidgets('启动显示主页:推荐加载失败,侧边栏导航可用', (tester) async {
    await pumpApp(tester);

    expect(find.text('MC Mod Helper'), findsOneWidget);
    expect(find.text('首页推荐'), findsOneWidget);
    // 分类在独立页签(IndexedStack 只展示当前页签)
    expect(find.text('模组分类'), findsNothing);
    expect(find.textContaining('加载失败'), findsOneWidget);
    // 侧边栏四个入口(测试窗口 800x600 走宽屏 NavigationRail)
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('侧边栏切换页签:分类页与搜索页各自展示', (tester) async {
    await pumpApp(tester);

    // 切到分类页签
    await tester.tap(find.text('分类'));
    await tester.pump(); // IndexedStack 切换,无路由动画
    expect(find.text('模组分类'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget); // 分类区错误
    expect(find.text('首页推荐'), findsNothing);

    // 切到搜索页签
    await tester.tap(find.text('搜索'));
    await tester.pump();
    expect(find.text('模组搜索'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('首页推荐'), findsNothing);
  });

  testWidgets('进入设置页,可修改主题/字体/推荐条数', (tester) async {
    // 放大测试窗口:设置页列表较长,默认 600 高的窗口下页面下方区块
    // 未被 ListView 懒构建,推荐条数滑条等控件会找不到
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    await tester.tap(find.text('设置'));
    await tester.pump(); // IndexedStack 切换;配置页无网络请求、无挂起计时器

    // 各设置区块都在(「设置」同时出现在侧边栏标签与页面标题)
    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('数据设置'), findsOneWidget);

    // 切换主题模式(下拉框) → 服务值变化(不触发主页重载,无新计时器)
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('亮色').last);
    await tester.pumpAndSettle(); // 主题过渡动画收尾
    expect(SettingsService.instance.themeMode, ThemeMode.light);

    // 拖字体滑条(第一个) → 松手提交,服务值变化
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pump();
    expect(SettingsService.instance.fontScale, greaterThan(1.0));

    // 拖推荐条数滑条(第二个,可能在可视区外,先滚动到可见)
    await tester.ensureVisible(find.byType(Slider).last);
    await tester.pump();
    await tester.drag(find.byType(Slider).last, const Offset(400, 0));
    await tester.pump();
    expect(SettingsService.instance.featuredNum, greaterThan(20));

    // 条数变化触发推荐页(离屏但已挂载)重新拉取:先走节流计时器再发请求,
    // 测试环境请求返回 400;必须显式推进假时钟,不能用 pumpAndSettle
    // (它会提前退出留下 pending Timer,与 pumpApp 里是同一个坑)
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // 切换渲染方法(主题设置里的 String 下拉框) → 服务值变化;
    // 渲染方法不触发主页重拉,无新计时器
    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hyper').last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.renderType, 'hyperViewer');

    // 切换推荐来源(数据设置里的 FeatureSource 下拉框) → 服务值变化,
    // 推荐页再次重拉
    await tester.ensureVisible(find.byType(DropdownButton<FeatureSource>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<FeatureSource>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最新编辑').last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.featuredSource, FeatureSource.lastEditTime);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // 数据来源下拉框切到 Modrinth(选项文本只在菜单打开后出现)
    expect(find.text('数据来源'), findsOneWidget);
    await tester.ensureVisible(find.byType(DropdownButton<ModSource>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<ModSource>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modrinth').last);
    // dataSource 变化触发推荐页与分类页重拉:推荐请求无节流立即发出,
    // 分类请求挂在 ModrinthApi 1s 节流计时器上,显式推进假时钟
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(SettingsService.instance.dataSource, ModSource.modrinth);

    // 展示方式下拉框(网格/列表/自适应) → 服务值变化;
    // 只换布局不重新拉取,无新计时器
    expect(find.text('展示方式'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<DisplayStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格').last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.displayStyle, DisplayStyle.card);
  });

  testWidgets('点击刷新按钮重新加载推荐', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump(); // 推荐区回到加载态
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('加载失败'), findsNothing);

    await tester.pump(const Duration(seconds: 1)); // 节流计时器触发
    await tester.pump(); // 请求 400 → setState
    await tester.pump(); // 渲染错误态
    expect(find.textContaining('加载失败'), findsOneWidget);
  });

  testWidgets('修改推荐条数上限后推荐重新拉取', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('加载失败'), findsOneWidget);

    SettingsService.instance.setFeaturedMax(30);
    await tester.pump(); // 触发重载 → 推荐区回到加载态
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('加载失败'), findsNothing);

    await tester.pump(const Duration(seconds: 1)); // 节流计时器触发
    await tester.pump(); // 请求 400 → setState
    await tester.pump(); // 渲染错误态
    expect(find.textContaining('加载失败'), findsOneWidget);
  });

  testWidgets('聚合搜索:来源按钮切换展示,失败来源单独报错', (tester) async {
    // 只给 ModrinthApi 注入假响应;mcmod 用真实客户端(测试环境固定 400),
    // 验证"单个来源失败不影响其它来源"的聚合行为
    ModrinthApi.clientFactory = () => MockClient((request) async {
      if (request.url.path == '/v2/search') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'hits': [
                {
                  'slug': 'jei',
                  'title': 'JEI',
                  'description': 'Just Enough Items',
                  'icon_url': null,
                  'downloads': 100,
                  'follows': 10,
                },
              ],
              'total_hits': 1,
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });
    ModrinthApi.clearCaches(); // 重置惰性客户端,让上面的工厂生效

    await pumpApp(tester);
    await tester.tap(find.text('搜索'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'jei');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump(); // 搜索发起
    await tester.pump(); // mcmod 400 → 失败;modrinth 命中
    await tester.pump(); // 渲染结果

    // mcmod 失败,默认展示回落到有结果的 Modrinth(设置来源 mcmod 无结果)
    expect(find.text('JEI'), findsOneWidget);
    // 左栏:mcmod 标注失败,modrinth 标注条数
    expect(find.text('MC百科 · 失败'), findsOneWidget);
    expect(find.text('Modrinth (1)'), findsOneWidget);

    // 切到 mcmod:右栏展示该来源的错误
    await tester.tap(find.text('MC百科 · 失败'));
    await tester.pump();
    expect(find.textContaining('HTTP 400'), findsOneWidget);
    expect(find.text('JEI'), findsNothing);

    // 切回 modrinth:恢复结果列表
    await tester.tap(find.text('Modrinth (1)'));
    await tester.pump();
    expect(find.text('JEI'), findsOneWidget);
  });
}
