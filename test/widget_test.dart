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
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/setting/theme_settings.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/render.dart';
import 'package:mc_mod_helper/service/value/source.dart';

/// 启动应用并推进到首页三个版块与分类页都完成失败渲染。
///
/// 测试环境中网络请求被禁用(返回 HTTP 400)。各页面挂在 IndexedStack
/// 中同时挂载,请求共用 mcmod www 的 1s 节流:一个发完下一个才轮到。
/// pumpAndSettle 会提前退出留下 pending Timer,因此这里显式推进假时钟。
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const McModHelper());
  // 首页三个版块各一次请求(顺序发起)+ 分类页一次,逐个推过节流计时器
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump(); // 渲染最终错误态
}

void main() {
  setUpAll(() async {
    // 收藏页挂在 IndexedStack 里随应用一起构建,卡片带收藏按钮,
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
    await ThemeSettings.instance.load();
    await DisplaySettings.instance.load();
    await LanguageSettings.instance.load();
    await AgentSettings.instance.load();
    // 重置各 Api 的节流时间戳与缓存:否则上个用例残留的请求时间
    // 会让"第一个请求立即发出"的节流节奏不可预测
    McmodApi.clearCaches();
    ModrinthApi.clearCaches();
  });

  testWidgets('启动显示主页:三个版块各加载失败,侧边栏导航可用', (tester) async {
    // 加高窗口:三个版块要同时在可视区才会被 ListView 构建
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    expect(find.text('MC Mod Helper'), findsOneWidget);
    // 首页三个版块(默认排序/最新收录/最新编辑),各带一个「查看更多」
    for (final title in ['默认排序', '最新收录', '最新编辑']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('查看更多'), findsNWidgets(3));
    // 三个版块都请求失败(测试环境 HTTP 400)
    expect(find.textContaining('加载失败'), findsNWidgets(3));
    // 分类在独立页签(IndexedStack 只展示当前页签)
    expect(find.text('模组分类'), findsNothing);
    // 侧边栏五个页签入口(测试窗口 800x600 走宽屏 NavigationRail;
    // 设置不再是页签,入口在主页 AppBar)
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    // 设置入口:主页 AppBar 一个,宽屏侧边栏底部还留了一个
    expect(find.byTooltip('设置'), findsWidgets);
    expect(find.byIcon(Icons.refresh), findsOneWidget); // 主页刷新按钮
  });

  testWidgets('侧边栏切换页签:分类与搜索', (tester) async {
    await pumpApp(tester);

    // 切到分类页签
    await tester.tap(find.text('分类'));
    await tester.pump(); // IndexedStack 切换,无路由动画
    expect(find.text('模组分类'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsWidgets); // 分类区错误
    expect(find.text('默认排序'), findsNothing); // 已离开首页

    // 切到搜索页签(IndexedStack 切换非选中页 offstage,
    // 设置页的输入框不会干扰 TextField 计数)
    await tester.tap(find.text('搜索'));
    await tester.pump();
    expect(find.text('模组搜索'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('进入设置页,可修改主题/显示/语言/AI 设置', (tester) async {
    // 放大测试窗口:设置页列表较长,默认 600 高的窗口下展开的分组
    // 会被 ListView 懒构建掉,滑条等控件会找不到
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    // 设置页从主页 AppBar 推开(不再是页签);无网络请求、无挂起计时器
    await tester.tap(find.byTooltip('设置').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // 路由过渡
    await tester.pump(const Duration(milliseconds: 350));

    // 五个分组标题都在,且默认全部折叠(子项不渲染)
    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    for (final title in ['主题', '显示', '语言', 'AI', '关于']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(DropdownButton<ThemeMode>), findsNothing);

    // ---- 主题:展开分组后切主题模式、字体与字号 ----
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle(); // 展开动画
    expect(find.text('字体选择'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('亮色').last);
    await tester.pumpAndSettle(); // 主题过渡动画收尾
    expect(ThemeSettings.instance.themeMode, ThemeMode.light);

    // 拖字体滑条(主题分组里唯一一个) → 松手提交,服务值变化
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pump();
    expect(ThemeSettings.instance.fontScale, greaterThan(1.0));

    // 切换字体(下拉框) → 服务值变化,主题 fontFamily 即时生效
    // (回归1:主题缓存键曾漏掉字体;回归2:字体搬到别的服务后顶层不再监听)
    // 注意:「语言」分组里的「目标语言」也是 DropdownButton<String>,
    // 字体下拉在页面更靠前,用 .first 取它
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unifont').last);
    await tester.pumpAndSettle(); // 新 ThemeData → 主题过渡动画收尾
    expect(ThemeSettings.instance.fontType, 'Unifont');
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme
          ?.textTheme
          .bodyMedium
          ?.fontFamily,
      'Unifont',
    );

    // ---- 显示:渲染方法/数据来源/展示方式 ----
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    expect(find.text('渲染方法'), findsOneWidget);
    expect(find.text('数据来源'), findsOneWidget);
    expect(find.text('展示方式'), findsOneWidget);

    // 切换渲染方法(RenderType 下拉框) → 服务值变化;
    // 渲染方法不触发主页重拉,无新计时器
    await tester.ensureVisible(find.byType(DropdownButton<RenderType>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<RenderType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hyper').last);
    await tester.pumpAndSettle();
    expect(DisplaySettings.instance.renderType, RenderType.hyper);

    // 数据来源下拉框切到 Modrinth(选项文本只在菜单打开后出现)
    await tester.ensureVisible(find.byType(DropdownButton<ModSource>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<ModSource>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modrinth').last);
    // dataSource 变化触发三个版块与分类页重拉:第一个请求无节流立即发出,
    // 后续请求挂在 ModrinthApi 1s 节流计时器上,显式推进假时钟
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(DisplaySettings.instance.dataSource, ModSource.modrinth);

    // 展示方式下拉框(网格/列表/自适应) → 服务值变化;
    // 只换布局不重新拉取,无新计时器
    await tester.tap(find.byType(DropdownButton<DisplayStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格').last);
    await tester.pumpAndSettle();
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.card);

    // ---- 语言:目标语言(详情页翻译按钮使用) ----
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButton<String>).last);
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('英语').last);
    await tester.pumpAndSettle();
    expect(LanguageSettings.instance.translateLang, 'en');

    // ---- AI:三项都是「点击弹出输入框」,弹窗里「确定」才写回 ----
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('接口地址'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);

    await tester.ensureVisible(find.text('接口地址'));
    await tester.pump();
    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle(); // 弹窗入场
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'https://api.deepseek.com/v1',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(AgentSettings.instance.baseUrl, 'https://api.deepseek.com/v1');
    // 行内展示跟着服务值刷新
    expect(find.text('https://api.deepseek.com/v1'), findsOneWidget);

    // 再点开清空 → 回落到默认地址
    await tester.tap(find.text('接口地址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(AgentSettings.instance.baseUrl, AgentSettings.defaultBaseUrl);
  });

  testWidgets('点击刷新按钮:三个版块重新加载', (tester) async {
    // 加高窗口:三个版块要同时在可视区才会被 ListView 构建
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump(); // 三个版块一起回到加载态
    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    expect(find.textContaining('加载失败'), findsNothing);

    // 三个请求依次受 1s 节流约束:逐个推进假时钟(不能用 pumpAndSettle)
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.textContaining('加载失败'), findsNWidgets(3));
  });

  testWidgets('「查看更多」进入对应版块的列表页', (tester) async {
    await pumpApp(tester);

    // 第一个「查看更多」属于「默认排序」版块
    await tester.tap(find.text('查看更多').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // 路由过渡
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.widgetWithText(AppBar, '默认排序'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsWidgets); // 列表页自带刷新

    // 列表页的首屏请求挂着 mcmod 的 1s 节流:推完它再结束,避免留下计时器
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  });

  testWidgets('切换数据来源后首页三个版块重新拉取', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('加载失败'), findsWidgets);

    DisplaySettings.instance.setDataSource(ModSource.modrinth);
    await tester.pump(); // 版块回到加载态
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // 三个版块依次请求,逐个推过节流计时器
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(DisplaySettings.instance.dataSource, ModSource.modrinth);
    expect(find.textContaining('加载失败'), findsWidgets);
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
    // 搜索入口:侧边栏「搜索」页签
    await tester.tap(find.text('搜索'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'jei');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump(); // 搜索发起
    await tester.pump(const Duration(seconds: 1)); // mcmod www 节流计时器 → 请求(400)
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
