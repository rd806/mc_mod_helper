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
    expect(DisplaySettings.instance.dataSource, ModSource.mcmod);
    expect(DisplaySettings.instance.renderType, RenderType.auto);
    expect(DisplaySettings.instance.displayStyle, DisplayStyle.table);
  });

  test('setter 写入持久化存储', () async {
    await DisplaySettings.instance.load();
    DisplaySettings.instance
      ..setDataSource(ModSource.modrinth)
      ..setDisplayStyle(DisplayStyle.card)
      ..setRenderType(RenderType.hyper);

    final prefs = await SharedPreferences.getInstance();
    // 存枚举的 name 字符串(读回时按 name 还原,枚举增删不影响旧数据)
    expect(prefs.getString('data_source'), 'modrinth');
    expect(prefs.getString('display_style'), 'card');
    expect(prefs.getString('render_type'), 'hyper');
  });

  test('load 能恢复已保存的设置(模拟重启)', () async {
    SharedPreferences.setMockInitialValues({
      'data_source': 'modrinth',
      'display_style': 'auto',
      'render_type': 'hyper',
    });
    await DisplaySettings.instance.load();
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
}
