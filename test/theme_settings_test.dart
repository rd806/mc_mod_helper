import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/setting/theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例重置 mock 存储;load() 对缺失键赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
  });

  test('load 在无存档时回到默认值', () async {
    await ThemeSettings.instance.load();
    expect(ThemeSettings.instance.themeMode, ThemeMode.system);
    expect(ThemeSettings.instance.seedColor.toARGB32(), Colors.blue.toARGB32());
    expect(ThemeSettings.instance.fontScale, 1.0);
    expect(ThemeSettings.instance.fontType, ThemeSettings.systemFont);
    // 系统字体不给 ThemeData 指定字体族,由引擎回退
    expect(ThemeSettings.instance.fontFamily, isNull);
  });

  test('setter 写入持久化存储', () async {
    await ThemeSettings.instance.load();
    ThemeSettings.instance
      ..setThemeMode(ThemeMode.dark)
      ..setSeedColor(Colors.orange)
      ..setFontScale(1.15)
      ..setFontType('Unifont');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getInt('seed_color'), Colors.orange.toARGB32());
    expect(prefs.getDouble('font_scale'), 1.15);
    expect(prefs.getString('font_type'), 'Unifont');
  });

  test('load 能恢复已保存的主题(模拟重启)', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'seed_color': Colors.deepPurple.toARGB32(),
      'font_scale': 0.9,
      'font_type': 'Unifont',
    });
    await ThemeSettings.instance.load();
    expect(ThemeSettings.instance.themeMode, ThemeMode.dark);
    expect(
      ThemeSettings.instance.seedColor.toARGB32(),
      Colors.deepPurple.toARGB32(),
    );
    expect(ThemeSettings.instance.fontScale, 0.9);
    expect(ThemeSettings.instance.fontType, 'Unifont');
  });

  test('主题模式非法存储值回落到默认', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'bogus'});
    await ThemeSettings.instance.load();
    expect(ThemeSettings.instance.themeMode, ThemeMode.system);
  });

  test('fontType 非法存储值与非法 setter 都忽略', () async {
    SharedPreferences.setMockInitialValues({'font_type': 'bogus'});
    await ThemeSettings.instance.load();
    expect(ThemeSettings.instance.fontType, ThemeSettings.systemFont);

    ThemeSettings.instance.setFontType('bogus');
    expect(ThemeSettings.instance.fontType, ThemeSettings.systemFont);
  });

  test('旧版本存的 NotoSansSC 已不再打包,加载时回落到系统字体', () async {
    SharedPreferences.setMockInitialValues({'font_type': 'NotoSansSC'});
    await ThemeSettings.instance.load();
    expect(ThemeSettings.instance.fontType, ThemeSettings.systemFont);
    expect(ThemeSettings.instance.fontFamily, isNull);
  });

  test('fontFamily 把系统字体映射成 null,其余原样交给 ThemeData', () async {
    await ThemeSettings.instance.load();
    ThemeSettings.instance.setFontType('Unifont');
    expect(ThemeSettings.instance.fontType, 'Unifont');
    expect(ThemeSettings.instance.fontFamily, 'Unifont');
  });

  test('fontScale 超出范围时被截断', () async {
    await ThemeSettings.instance.load();
    ThemeSettings.instance.setFontScale(5);
    expect(ThemeSettings.instance.fontScale, ThemeSettings.fontMax);
    ThemeSettings.instance.setFontScale(0.1);
    expect(ThemeSettings.instance.fontScale, ThemeSettings.fontMin);
  });
}
