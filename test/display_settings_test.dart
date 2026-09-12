import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/render.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例重置 mock 存储;load() 对缺失键赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
  });

  test('load 在无存档时回到默认值', () async {
    await DisplaySettings.instance.load();
    expect(DisplaySettings.instance.featuredNum, 20);
    expect(DisplaySettings.instance.featuredSource, FeatureSource.none);
    expect(DisplaySettings.instance.dataSource, ModSource.mcmod);
    expect(DisplaySettings.instance.renderType, RenderType.auto);
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.table);
  });

  test('setter 写入持久化存储', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance
      ..setFeaturedMax(35)
      ..setFeaturedSource(FeatureSource.lastEditTime)
      ..setDataSource(ModSource.modrinth)
      ..setDisplayStyle(DisplayStyle.card)
      ..setRenderType(RenderType.hyper);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('featured_max'), 35);
    // 存枚举的 name 字符串(与 data_source 一致)
    expect(prefs.getString('featured_source'), 'lastEditTime');
    expect(prefs.getString('data_source'), 'modrinth');
    expect(prefs.getString('display_style'), 'card');
    expect(prefs.getString('render_type'), 'hyper');
  });

  test('load 能恢复已保存的设置(模拟重启)', () async {
    SharedPreferences.setMockInitialValues({
      'featured_max': 45,
      'featured_source': 'lastEditTime',
      'data_source': 'modrinth',
      'display_style': 'auto',
      'render_type': 'hyper',
    });
    await DisplaySettings.instance.load();
    expect(DisplaySettings.instance.featuredNum, 45);
    expect(DisplaySettings.instance.featuredSource, FeatureSource.lastEditTime);
    expect(DisplaySettings.instance.dataSource, ModSource.modrinth);
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.auto);
    expect(DisplaySettings.instance.renderType, RenderType.hyper);
  });

  test('dataSource setter 生效', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance.setDataSource(ModSource.modrinth);
    expect(DisplaySettings.instance.dataSource, ModSource.modrinth);
  });

  test('renderType 非法存储值回落到默认', () async {
    SharedPreferences.setMockInitialValues({'render_type': 'bogus'});
    await DisplaySettings.instance.load();
    expect(DisplaySettings.instance.renderType, RenderType.auto);
  });

  test('featuredSource setter 生效', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance.setFeaturedSource(FeatureSource.lastEditTime);
    expect(DisplaySettings.instance.featuredSource, FeatureSource.lastEditTime);
    // 同值短路,不写盘不通知
    DisplaySettings.instance.setFeaturedSource(FeatureSource.lastEditTime);
    expect(DisplaySettings.instance.featuredSource, FeatureSource.lastEditTime);
  });

  test('featuredSource 非法存储值回落到默认', () async {
    SharedPreferences.setMockInitialValues({'featured_source': 'bogus'});
    await DisplaySettings.instance.load();
    expect(DisplaySettings.instance.featuredSource, FeatureSource.none);
  });

  test('displayStyle setter 生效', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance.setDisplayStyle(DisplayStyle.card);
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.card);
    // 同值短路,不写盘不通知
    DisplaySettings.instance.setDisplayStyle(DisplayStyle.card);
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.card);
  });

  test('displayStyle 非法存储值回落到默认的列表式', () async {
    SharedPreferences.setMockInitialValues({'display_style': 'bogus'});
    await DisplaySettings.instance.load();
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.table);
  });

  test('featuredMax 超出范围时被截断', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance.setFeaturedMax(500);
    expect(DisplaySettings.instance.featuredNum, 50);
    DisplaySettings.instance.setFeaturedMax(1);
    expect(DisplaySettings.instance.featuredNum, 5);
  });
}
