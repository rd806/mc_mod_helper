import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例重置 mock 存储;load() 对缺失键赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
  });

  test('load 在无存档时回到默认语言', () async {
    await LanguageSettings.instance.load();
    expect(
      LanguageSettings.instance.translateLang,
      LanguageSettings.defaultTranslateLang,
    );
  });

  test('setter 写入并可恢复', () async {
    await LanguageSettings.instance.load();
    LanguageSettings.instance.setTranslateLang('en');
    expect(LanguageSettings.instance.translateLangLabel, '英语');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('translate_lang'), 'en');

    // 模拟重启恢复
    SharedPreferences.setMockInitialValues({'translate_lang': 'en'});
    await LanguageSettings.instance.load();
    expect(LanguageSettings.instance.translateLang, 'en');
  });

  test('非法存储值与非法 setter 都忽略', () async {
    SharedPreferences.setMockInitialValues({'translate_lang': 'klingon'});
    await LanguageSettings.instance.load();
    expect(LanguageSettings.instance.translateLang, 'zh-Hans');

    LanguageSettings.instance.setTranslateLang('klingon');
    expect(LanguageSettings.instance.translateLang, 'zh-Hans');
  });

  test('目标语言的展示名', () async {
    await LanguageSettings.instance.load();
    expect(LanguageSettings.instance.translateLangLabel, '简体中文');
  });
}
