import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/render.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内容显示设置(渲染方法/数据来源/展示方式):
/// 单例 ChangeNotifier + shared_preferences 持久化。
///
/// 主题模式/强调色/字体/字号属于 [SettingsService](会重建整个应用),
/// 这里只放切换后不需要重建主题、但页面要跟着刷新的设置。
class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();

  /// 全局唯一实例
  static final DisplaySettings instance = DisplaySettings._();

  static const String _dataSourceKey = 'data_source';
  static const String _displayStyleKey = 'display_style';
  static const String _renderTypeKey = 'render_type';

  /// 搜索/详情数据来源的合法取值
  static const List<ModSource> dataSources = [
    ModSource.mcmod,
    ModSource.modrinth,
    ModSource.curseforge,
  ];

  /// 正文渲染方法
  static const List<RenderType> renderTypes = [
    RenderType.auto,
    RenderType.hyper,
  ];

  /// 模组展示方法
  static const List<DisplayStyle> displayStyles = [
    DisplayStyle.card,
    DisplayStyle.table,
    DisplayStyle.auto,
  ];

  ModSource _dataSource = ModSource.mcmod;
  DisplayStyle _displayStyle = DisplayStyle.table;
  RenderType _renderType = RenderType.auto;

  ModSource get dataSource => _dataSource;
  DisplayStyle get displayStyle => _displayStyle;
  RenderType get renderType => _renderType;

  /// 启动时读取已保存的设置(在 runApp 前调用)。
  ///
  /// 每个键缺失或解析失败时都显式回落到默认值(而非保持内存现值),
  /// 因此测试里可以用 setMockInitialValues({}) + load() 把单例重置为默认。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ds = prefs.getString(_dataSourceKey);
      ModSource modSource = SourceManager.sourceToString(ds);
      _dataSource = (ds != null && dataSources.contains(modSource))
          ? modSource
          : ModSource.mcmod;

      // 展示方式(未知存储值回落到默认的列表式)
      _displayStyle = DisplayManager.displayToString(
        prefs.getString(_displayStyleKey),
      );

      final rt = prefs.getString(_renderTypeKey);
      RenderType renderType = RenderManager.displayToString(rt);
      _renderType = (rt != null && renderTypes.contains(renderType))
          ? renderType
          : RenderType.auto;

      notifyListeners();
    } catch (_) {
      // 读取失败:保持默认值,不阻塞启动
    }
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

  /// 设置正文渲染方法(与 setDataSource 一致:非法值忽略,同值短路)
  void setRenderType(RenderType type) {
    if (!renderTypes.contains(type) || type == _renderType) return;
    _renderType = type;
    notifyListeners();
    _persist(_renderTypeKey, type.name);
  }

  /// 设置模组信息展示方式(卡片式/列表式/自适应式),非法值忽略
  void setDisplayStyle(DisplayStyle style) {
    if (!displayStyles.contains(style) || style == _displayStyle) return;
    _displayStyle = style;
    notifyListeners();
    _persist(_displayStyleKey, style.name);
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
