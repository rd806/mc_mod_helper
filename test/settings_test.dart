import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/service/settings.dart';

void main() {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
        // 每个用例重置 mock 存储;load() 对缺失键赋默认值,单例随之复位
        SharedPreferences.setMockInitialValues({});
    });

    test('load 在无存档时回到默认值', () async {
    await SettingsService.instance.load();
    expect(SettingsService.instance.themeMode, ThemeMode.system);
    expect(
        SettingsService.instance.seedColor.toARGB32(),
        Colors.blue.toARGB32(),
    );
    expect(SettingsService.instance.fontScale, 1.0);
    expect(SettingsService.instance.featuredMax, 20);
    expect(SettingsService.instance.featuredSource, 'createtime');
    });

    test('setter 写入持久化存储', () async {
    await SettingsService.instance.load();
    SettingsService.instance
        ..setThemeMode(ThemeMode.dark)
        ..setSeedColor(Colors.orange)
        ..setFontScale(1.15)
        ..setFeaturedMax(35)
        ..setFeaturedSource('lastedittime');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getInt('seed_color'), Colors.orange.toARGB32());
    expect(prefs.getDouble('font_scale'), 1.15);
    expect(prefs.getInt('featured_max'), 35);
    expect(prefs.getString('featured_source'), 'lastedittime');
    });

    test('load 能恢复已保存的设置(模拟重启)', () async {
    SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'seed_color': Colors.deepPurple.toARGB32(),
        'font_scale': 0.9,
        'featured_max': 45,
        'featured_source': 'lastedittime',
    });
    await SettingsService.instance.load();
    expect(SettingsService.instance.themeMode, ThemeMode.dark);
    expect(
        SettingsService.instance.seedColor.toARGB32(),
        Colors.deepPurple.toARGB32(),
    );
    expect(SettingsService.instance.fontScale, 0.9);
    expect(SettingsService.instance.featuredMax, 45);
    expect(SettingsService.instance.featuredSource, 'lastedittime');
    });

    test('featuredSource 非法值被忽略', () async {
    await SettingsService.instance.load();
    SettingsService.instance.setFeaturedSource('bogus');
    expect(SettingsService.instance.featuredSource, 'createtime');
    SettingsService.instance.setFeaturedSource('lastedittime');
    expect(SettingsService.instance.featuredSource, 'lastedittime');
    });

    test('featuredMax 超出范围时被截断', () async {
    await SettingsService.instance.load();
    SettingsService.instance.setFeaturedMax(500);
    expect(SettingsService.instance.featuredMax, 50);
    SettingsService.instance.setFeaturedMax(1);
    expect(SettingsService.instance.featuredMax, 5);
    });
}
