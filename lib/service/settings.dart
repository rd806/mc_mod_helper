import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';
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
  static const String _featuredTypeKey = 'featured_source';
  static const String _dataSourceKey = 'data_source';
  static const String _renderTypeKey = 'render_type';

  /// 字体大小
  static const double fontMin = 0.5;
  static const double fontMax = 2.0;

  /// 推荐列表条数上限的允许范围(与设置页滑条保持一致)
  static const int featuredMin = 5;
  static const int featuredMax = 50;

  /// 首页推荐来源的合法取值(与 mcmod.cn 列表页 sort 参数一致)
  static const List<FeatureSource> featuredTypes = [
    FeatureSource.none,
    FeatureSource.createTime,
    FeatureSource.lastEditTime,
  ];

  /// 搜索/详情数据来源的合法取值
  static const List<ModSource> dataSources = [
    ModSource.mcmod,
    ModSource.modrinth,
    ModSource.curseforge,
  ];

  /// 渲染方法
  static const List<String> renderTypes = ['default', 'hyperViewer'];

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = Colors.blue;
  double _fontScale = 1.0;
  int _featuredNum = 20;
  FeatureSource _featuredType = FeatureSource.none;
  ModSource _dataSource = ModSource.mcmod;
  String _renderType = 'default';

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  double get fontScale => _fontScale;
  int get featuredNum => _featuredNum;
  FeatureSource get featuredSource => _featuredType;
  ModSource get dataSource => _dataSource;
  String get renderType => _renderType;

  /// 启动时读取已保存的设置(在 runApp 前调用,避免启动后主题/字体跳变)。
  ///
  /// 每个键缺失或解析失败时都显式回落到默认值(而非保持内存现值),
  /// 因此测试里可以用 setMockInitialValues({}) + load() 把单例重置为默认。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 主题模式
      _themeMode =
          ThemeMode.values.asNameMap()[prefs.getString(_themeModeKey)] ??
          ThemeMode.system;
      _seedColor = Color(prefs.getInt(_seedColorKey) ?? Colors.blue.toARGB32());
      // 字体大小
      _fontScale = (prefs.getDouble(_fontScaleKey) ?? 1.0).clamp(
        fontMin,
        fontMax,
      );
      _featuredNum = (prefs.getInt(_featuredMaxKey) ?? 20).clamp(
        featuredMin,
        featuredMax,
      );

      final type = prefs.getString(_featuredTypeKey);
      FeatureSource featureSource = SourceManager.featureToString(type);
      _featuredType = (type != null && featuredTypes.contains(featureSource))
          ? featureSource
          : FeatureSource.none;

      final ds = prefs.getString(_dataSourceKey);
      ModSource modSource = SourceManager.sourceToString(ds);
      _dataSource = (ds != null && dataSources.contains(modSource))
          ? modSource
          : ModSource.mcmod;

      final rt = prefs.getString(_renderTypeKey);
      _renderType = (rt != null && renderTypes.contains(rt)) ? rt : 'default';

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
  void setFeaturedSource(FeatureSource source) {
    if (!featuredTypes.contains(source) || source == _featuredType) {
      return;
    }
    _featuredType = source;
    notifyListeners();
    // 与 setDataSource 同理:存 name 字符串而非枚举对象,
    // 否则 _persist 的 switch 没有对应分支,什么都不会写入
    _persist(_featuredTypeKey, source.name);
  }

  /// 设置搜索/详情数据来源(MC百科/Modrinth),非法值忽略
  void setDataSource(ModSource source) {
    if (!dataSources.contains(source) || source == _dataSource) return;
    _dataSource = source;
    notifyListeners();
    // 磁盘存枚举的 name 字符串(与 setThemeMode 存 mode.name 一致);
    // 直接存枚举对象的话 _persist 的 switch 没有对应分支,什么都不会写入
    _persist(_dataSourceKey, source.name);
  }

  /// 设置首页推荐列表条数上限(自动截断到允许范围)
  void setFeaturedMax(int max) {
    final clamped = max.clamp(featuredMin, featuredMax);
    if (clamped == _featuredNum) return;
    _featuredNum = clamped;
    notifyListeners();
    _persist(_featuredMaxKey, clamped);
  }

  /// 设置正文渲染方法(与 setDataSource 一致:非法值忽略,同值短路)
  void setRenderType(String type) {
    if (!renderTypes.contains(type) || type == _renderType) return;
    _renderType = type;
    notifyListeners();
    _persist(_renderTypeKey, type);
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
