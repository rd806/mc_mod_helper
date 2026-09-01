import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置(主题模式/强调色/字体缩放/推荐列表条数上限):
/// 单例 ChangeNotifier + shared_preferences 持久化
class SettingsService extends ChangeNotifier {
  SettingsService._();

  /// 全局唯一实例
  static final SettingsService instance = SettingsService._();

  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _fontScaleKey = 'font_scale';
  static const String _featuredMaxKey = 'featured_max';
  static const String _featuredSourceKey = 'featured_source';

  /// 字体大小
  static const double fontMin = 0.5;
  static const double fontMax = 2.0;

  /// 推荐列表条数上限的允许范围(与设置页滑条保持一致)
  static const int featuredMin = 5;
  static const int featuredMaxLimit = 50;

  /// 首页推荐来源的合法取值(与 mcmod.cn 列表页 sort 参数一致)
  static const List<String> featuredSources = [
    '',
    'createtime',
    'lastedittime',
  ];

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = Colors.blue;
  double _fontScale = 1.0;
  int _featuredMax = 20;
  String _featuredSource = "";

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  double get fontScale => _fontScale;
  int get featuredMax => _featuredMax;
  String get featuredSource => _featuredSource;

  /// 启动时读取已保存的设置(在 runApp 前调用,避免启动后主题/字体跳变)。
  ///
  /// 每个键缺失或解析失败时都显式回落到默认值(而非保持内存现值),
  /// 因此测试里可以用 setMockInitialValues({}) + load() 把单例重置为默认。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode =
          ThemeMode.values.asNameMap()[prefs.getString(_themeModeKey)] ??
          ThemeMode.system;
      _seedColor = Color(prefs.getInt(_seedColorKey) ?? Colors.blue.toARGB32());
      _fontScale = (prefs.getDouble(_fontScaleKey) ?? 1.0).clamp(
        fontMin,
        fontMax,
      );
      _featuredMax = (prefs.getInt(_featuredMaxKey) ?? 20).clamp(
        featuredMin,
        featuredMaxLimit,
      );
      final source = prefs.getString(_featuredSourceKey);
      _featuredSource = (source != null && featuredSources.contains(source))
          ? source
          : 'createtime';
      notifyListeners();
    } catch (_) {
      // 读取失败:保持默认值,不阻塞启动
    }
  }

  /// 切换主题模式:先同步更新内存值让 UI 立即生效,再异步写盘
  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    _persist(_themeModeKey, mode.name);
  }

  /// 设置强调色(亮/暗主题共用的种子色)
  void setSeedColor(Color color) {
    if (color.toARGB32() == _seedColor.toARGB32()) return;
    _seedColor = color;
    notifyListeners();
    _persist(_seedColorKey, color.toARGB32());
  }

  /// 设置全局字体缩放(自动截断到允许范围)
  void setFontScale(double scale) {
    final clamped = scale.clamp(fontMin, fontMax);
    if (clamped == _fontScale) return;
    _fontScale = clamped;
    notifyListeners();
    _persist(_fontScaleKey, clamped);
  }

  /// 设置首页推荐来源(最新收录/最新编辑),非法值忽略
  void setFeaturedSource(String source) {
    if (!featuredSources.contains(source) || source == _featuredSource) {
      return;
    }
    _featuredSource = source;
    notifyListeners();
    _persist(_featuredSourceKey, source);
  }

  /// 设置首页推荐列表条数上限(自动截断到允许范围)
  void setFeaturedMax(int max) {
    final clamped = max.clamp(featuredMin, featuredMaxLimit);
    if (clamped == _featuredMax) return;
    _featuredMax = clamped;
    notifyListeners();
    _persist(_featuredMaxKey, clamped);
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
        default:
          await prefs.setString(key, value as String);
      }
    } catch (_) {
      // 忽略写盘失败
    }
  }
}
