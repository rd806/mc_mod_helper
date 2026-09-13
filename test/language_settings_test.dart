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

  test('自动翻译:默认关闭,缺失键回落到默认', () async {
    await LanguageSettings.instance.load();
    expect(
      LanguageSettings.instance.autoTranslate,
      LanguageSettings.defaultAutoTranslate,
    );
  });

  test('自动翻译:setter 写盘并可恢复(回归:bool 曾存不下来)', () async {
    await LanguageSettings.instance.load();
    LanguageSettings.instance.setAutoTranslate(true);

    // 曾经 _persist 的 switch 没有 bool 分支,会走 `value as String`
    // 抛异常被 catch 吞掉 —— 表现为开关切了但永远存不下来
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_translate'), isTrue);

    // 模拟重启:开关状态必须能读回来,否则功能重启即失效
    SharedPreferences.setMockInitialValues({'auto_translate': true});
    await LanguageSettings.instance.load();
    expect(LanguageSettings.instance.autoTranslate, isTrue);
  });

  test('自动翻译:同值 setter 不通知', () async {
    await LanguageSettings.instance.load();
    var notifications = 0;
    void listener() => notifications++;
    LanguageSettings.instance.addListener(listener);
    addTearDown(() => LanguageSettings.instance.removeListener(listener));

    // 已经是关闭状态,再设一次关闭不应该通知
    LanguageSettings.instance.setAutoTranslate(
      LanguageSettings.defaultAutoTranslate,
    );
    expect(notifications, 0);

    LanguageSettings.instance.setAutoTranslate(true);
    expect(notifications, 1);
  });
}
