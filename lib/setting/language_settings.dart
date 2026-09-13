import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置(主题模式/强调色/字体缩放/推荐列表条数上限):
/// 单例 ChangeNotifier + shared_preferences 持久化
class LanguageSettings extends ChangeNotifier {
  LanguageSettings._();

  /// 全局唯一实例
  static final LanguageSettings instance = LanguageSettings._();

  static const String _translateLangKey = 'translate_lang';
  static const String _autoTranslateKey = 'auto_translate';

  /// 翻译目标语言:(显示名, 语言代码)
  static const List<(String, String)> translateLanguages = [
    ('简体中文', 'zh-Hans'),
    ('繁体中文', 'zh-Hant'),
    ('英语', 'en'),
    ('日语', 'ja'),
    ('韩语', 'ko'),
    ('俄语', 'ru'),
    ('法语', 'fr'),
    ('德语', 'de'),
    ('西班牙语', 'es'),
  ];

  /// 翻译目标语言的默认值
  static const String defaultTranslateLang = 'zh-Hans';

  /// 自动翻译默认值
  static const bool defaultAutoTranslate = false;

  // 翻译目标语言(AI 接口地址/Key/模型由 AgentSettings 管理)
  String _translateLang = defaultTranslateLang;
  // 自动翻译
  bool _autoTranslate = defaultAutoTranslate;

  /// 翻译目标语言(
  String get translateLang => _translateLang;

  /// 自动翻译
  bool get autoTranslate => _autoTranslate;

  /// 目标语言的展示名(未知代码回落到代码本身)
  String get translateLangLabel {
    for (final (label, code) in translateLanguages) {
      if (code == _translateLang) return label;
    }
    return _translateLang;
  }

  /// 启动时读取已保存的设置(在 runApp 前调用,避免启动后主题/字体跳变)。
  ///
  /// 每个键缺失或解析失败时都显式回落到默认值(而非保持内存现值),
  /// 因此测试里可以用 setMockInitialValues({}) + load() 把单例重置为默认。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 翻译目标语言(未知语言代码回落到默认)
      final lang = prefs.getString(_translateLangKey);
      _translateLang =
          (lang != null && translateLanguages.any((e) => e.$2 == lang))
          ? lang
          : defaultTranslateLang;
      // 自动翻译(缺失键回落到默认的关闭)
      _autoTranslate = prefs.getBool(_autoTranslateKey) ?? defaultAutoTranslate;

      notifyListeners();
    } catch (_) {
      // 读取失败:保持默认值,不阻塞启动
    }
  }

  /// 翻译目标语言(未知语言代码忽略)
  void setTranslateLang(String lang) {
    if (!translateLanguages.any((e) => e.$2 == lang) ||
        lang == _translateLang) {
      return;
    }
    _translateLang = lang;
    notifyListeners();
    _persist(_translateLangKey, lang);
  }

  /// 自动翻译(同值短路,与其余 setter 一致)
  void setAutoTranslate(bool auto) {
    if (auto == _autoTranslate) return;
    _autoTranslate = auto;
    notifyListeners();
    _persist(_autoTranslateKey, auto);
  }

  /// 异步写盘;失败不影响本次切换,仅下次启动回到上次成功保存的值
  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (value) {
        case final int i:
          await prefs.setInt(key, i);
        case final double d:
          await prefs.setDouble(key, d);
        // bool 必须单独一支:落到 default 会被强转成 String 抛异常,
        // 又被下面的 catch 吞掉,表现为"开关切了但永远存不下来"
        case final bool b:
          await prefs.setBool(key, b);
        default:
          await prefs.setString(key, value as String);
      }
    } catch (_) {
      // 忽略写盘失败
    }
  }
}
