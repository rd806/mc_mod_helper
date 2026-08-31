import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/main.dart';
import 'package:mc_mod_helper/service/settings.dart';

/// 启动应用并推进到主页两个加载区(分类/推荐)都完成失败渲染。
///
/// 测试环境中网络请求被禁用(返回 HTTP 400),分类与推荐请求共用节流,
/// 推荐请求会挂起在约 1 秒的间隔计时器上;pumpAndSettle 会提前退出
/// 留下 pending Timer,因此这里显式推进假时钟。
Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const McModHelper());
    await tester.pump(); // 分类请求 400 → setState
    await tester.pump(const Duration(seconds: 1)); // 间隔计时器触发 → 推荐请求发出
    await tester.pump(); // 推荐 400 → setState
    await tester.pump(); // 渲染最终错误态
}

void main() {
    setUp(() async {
    // 单例跨用例共享:重置 mock 存储并 load,
    // load 对缺失键显式赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    });

    testWidgets('启动显示主页:分类与推荐加载失败,搜索与设置入口可用', (tester) async {
    await pumpApp(tester);

    expect(find.text('MC百科'), findsOneWidget);
    expect(find.text('模组分类'), findsOneWidget);
    expect(find.text('首页推荐'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsNWidgets(2));
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('点击搜索图标进入搜索页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle(); // 仅路由动画,无挂起计时器

    expect(find.text('模组搜索'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('点击设置图标进入设置页,可修改主题/字体/推荐条数', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(); // 仅路由动画;配置页无网络请求、无挂起计时器

    // 三个设置区块都在
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题选择'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('列表长度'), findsOneWidget);

    // 切换主题模式 → 服务值变化(不触发主页重载,无新计时器)
    await tester.tap(find.text('亮色'));
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
    expect(SettingsService.instance.featuredMax, greaterThan(20));

    // 条数变化触发主页(离屏但已挂载)重新拉取:先走节流计时器再发请求,
    // 测试环境请求返回 400;必须显式推进假时钟,不能用 pumpAndSettle
    // (它会提前退出留下 pending Timer,与 pumpApp 里是同一个坑)
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    });

    testWidgets('点击刷新按钮重新加载本页', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump(); // 两个区块回到加载态
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.textContaining('加载失败'), findsNothing);

    await tester.pump(const Duration(seconds: 1)); // 两个节流计时器触发
    await tester.pump(); // 请求 400 → setState
    await tester.pump(); // 渲染错误态
    expect(find.textContaining('加载失败'), findsNWidgets(2));
    });

    testWidgets('修改推荐条数上限后主页重新拉取推荐', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('加载失败'), findsNWidgets(2));

    SettingsService.instance.setFeaturedMax(30);
    await tester.pump(); // 触发重载 → 推荐区回到加载态
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1)); // 节流计时器触发
    await tester.pump(); // 请求 400 → setState
    await tester.pump(); // 渲染错误态
    expect(find.textContaining('加载失败'), findsNWidgets(2));
    });
}
