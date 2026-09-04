import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';
import 'package:mc_mod_helper/widget/link_icons.dart';

import '../service/settings.dart';

/// 设置页:主题(模式/强调色)、字体大小、推荐列表条数上限
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  /// 推荐条数滑条草稿值:拖动过程中只改草稿,松手(onChangeEnd)才提交,
  /// 避免每个档位变化都触发主页重新拉取(多页抓取耗时较长)
  late double _featuredDraft = SettingsService.instance.featuredNum.toDouble();

  /// 字体缩放滑条草稿值(独立于推荐条数草稿)
  late double _fontScaleDraft = SettingsService.instance.fontScale.clamp(
    SettingsService.fontMin,
    SettingsService.fontMax,
  );

  /// 系统主题
  static const List<(String, ThemeMode)> _themeMode = [
    ('跟随系统', ThemeMode.system),
    ('亮色', ThemeMode.light),
    ('暗色', ThemeMode.dark),
  ];

  /// 可选强调色：名称 + 色值
  static const List<(String, Color)> _seedColors = [
    ('蓝色', Colors.blue),
    ('绿色', Colors.green),
    ('紫色', Colors.deepPurple),
    ('橙色', Colors.orange),
    ('红色', Colors.red),
  ];

  // 推荐方法
  // 与 settings 中的一致(语义对应 mcmod 列表页 sort 参数:
  // createtime=最新收录,lastedittime=最新编辑)
  static const List<(String, FeatureSource)> _sortMethod = [
    ('默认', FeatureSource.none),
    ('最新收录', FeatureSource.createTime),
    ('最新编辑', FeatureSource.lastEditTime),
  ];

  static const List<(String, String)> _renderType = [
    ('默认', 'default'),
    ('Hyper', 'hyperViewer'),
  ];

  static const List<(String, ModSource)> _modSource = [
    ('MC百科', ModSource.mcmod),
    ('Modrinth', ModSource.modrinth),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      // 页面级监听:一个 ListenableBuilder 覆盖三个区块,
      // 设置变化即时反映到控件选中态
      body: ListenableBuilder(
        listenable: SettingsService.instance,
        builder: (context, _) {
          final s = SettingsService.instance;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _sectionTitle(context, '主题设置'),
              _buildThemeModeSection(context, s),
              _buildSeedColorSection(context, s),
              _buildRenderType(context, s),
              _sectionTitle(context, '字体设置'),
              _buildFontScaleSection(context, s),
              _sectionTitle(context, '首页设置'),
              _buildDataSourceSection(context, s),
              _buildListSource(context, s),
              _buildListMaxSection(context, s),
            ],
          );
        },
      ),
    );
  }

  /// 配置项标题
  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  /// 主题模式；跟随系统 / 亮色 / 暗色。
  Widget _buildThemeModeSection(BuildContext context, SettingsService s) {
    final themeMode = s.themeMode;
    final theme = Theme.of(context);
    // 将 _themeMode 转换为 DropdownMenuItem 列表
    final dropdownItems = _themeMode.map<DropdownMenuItem<ThemeMode>>((item) {
      final (label, value) = item;
      return DropdownMenuItem<ThemeMode>(
        value: value,
        child: Row(
          children: [
            Icon(_getIconForThemeMode(value)),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      );
    }).toList();
    // 确定当前选中的值（防御性处理）
    final selectedValue = _themeMode.any((f) => f.$2 == themeMode)
        ? themeMode
        : ThemeMode.system;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text('主题选择', style: theme.textTheme.bodyMedium),
          const Spacer(),
          // 使用下拉框
          DropdownButton<ThemeMode>(
            value: selectedValue,
            items: dropdownItems,
            onChanged: (ThemeMode? newValue) {
              if (newValue != null) {
                SettingsService.instance.setThemeMode(newValue);
              }
            },
            // 样式定制（可选）
            style: theme.textTheme.bodyMedium,
            // 设置为透明下划线
            underline: Container(height: 0, color: Colors.transparent),
            icon: Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
            // 如果希望下拉框宽度自适应内容
            isDense: false,
            // 禁用焦点和悬停效果
            focusColor: Colors.transparent,
          ),
        ],
      ),
    );
  }

  // 获取图标
  IconData _getIconForThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.settings_suggest;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  /// 强调色:一行色块,选中项画外圈 + 对勾
  Widget _buildSeedColorSection(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);
    final selectedArgb = s.seedColor.toARGB32();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text('颜色种子', style: theme.textTheme.bodyMedium),
          Spacer(),
          for (final (label, color) in _seedColors)
            _buildColor(label, color, selectedArgb, theme),
        ],
      ),
    );
  }

  // 颜色按钮
  Widget _buildColor(
    String label,
    Color color,
    int selectedArgb,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => SettingsService.instance.setSeedColor(color),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selectedArgb == color.toARGB32()
                    ? theme.colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: selectedArgb == color.toARGB32()
                ? Icon(
                    Icons.check,
                    size: 20,
                    // 按色块明暗选白/黑对勾
                    color:
                        ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// 字体大小滑块
  Widget _buildFontScaleSection(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('字体大小', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${_fontScaleDraft.toStringAsFixed(2)}×',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _fontScaleDraft,
            min: SettingsService.fontMin,
            max: SettingsService.fontMax,
            divisions: 15, // 步进 0.1,刻度包含默认值 1.0
            label: '${_fontScaleDraft.toStringAsFixed(2)}×',
            onChanged: (v) => setState(() => _fontScaleDraft = v),
            onChangeEnd: (v) => SettingsService.instance.setFontScale(v),
          ),
        ],
      ),
    );
  }

  /// 搜索/详情数据来源(MC百科/Modrinth),修改后持久化
  Widget _buildDataSourceSection(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);

    // 转换为 DropdownMenuItem 列表
    final dropdownItems = _modSource.map<DropdownMenuItem<ModSource>>((item) {
      final (label, value) = item;
      return DropdownMenuItem<ModSource>(
        value: value,
        child: Row(
          children: [
            Icon(_getIconForDataSource(value)),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      );
    }).toList();

    final selectedValue = SettingsService.dataSources.contains(s.dataSource)
        ? s.dataSource
        : ModSource.mcmod;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text('数据来源', style: theme.textTheme.bodyMedium),
          Spacer(),
          // 使用下拉框
          DropdownButton<ModSource>(
            value: selectedValue,
            items: dropdownItems,
            onChanged: (ModSource? newValue) {
              if (newValue != null) {
                SettingsService.instance.setDataSource(newValue);
              }
            },
            // 样式定制（可选）
            style: theme.textTheme.bodyMedium,
            // 设置为透明下划线
            underline: Container(height: 0, color: Colors.transparent),
            icon: Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
            // 如果希望下拉框宽度自适应内容
            isDense: false,
            // 禁用焦点和悬停效果
            focusColor: Colors.transparent,
          ),
        ],
      ),
    );
  }

  // 获取图标
  IconData _getIconForDataSource(ModSource source) {
    switch (source) {
      case ModSource.mcmod:
        return LinkIcons.mc;
      case ModSource.modrinth:
        return LinkIcons.modrinth;
      case ModSource.curseforge:
        return LinkIcons.curseforge;
    }
  }

  /// 推荐列表来源(最新收录/最新编辑),修改后持久化,主页监听变化自动重拉
  Widget _buildListSource(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);

    // 转换为 DropdownMenuItem 列表
    final dropdownItems = _sortMethod.map<DropdownMenuItem<FeatureSource>>((
      item,
    ) {
      final (label, value) = item;
      return DropdownMenuItem<FeatureSource>(value: value, child: Text(label));
    }).toList();

    final selectedValue =
        SettingsService.featuredTypes.contains(s.featuredSource)
        ? s.featuredSource
        : FeatureSource.none;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text('推荐来源', style: theme.textTheme.bodyMedium),
          Spacer(),
          // 使用下拉框
          DropdownButton<FeatureSource>(
            value: selectedValue,
            items: dropdownItems,
            onChanged: (FeatureSource? newValue) {
              if (newValue != null) {
                SettingsService.instance.setFeaturedSource(newValue);
              }
            },
            // 样式定制（可选）
            style: theme.textTheme.bodyMedium,
            // 设置为透明下划线
            underline: Container(height: 0, color: Colors.transparent),
            icon: Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
            // 如果希望下拉框宽度自适应内容
            isDense: false,
            // 禁用焦点和悬停效果
            focusColor: Colors.transparent,
          ),
        ],
      ),
    );
  }

  /// 推荐列表条数上限:滑条 5–50,步进 5(divisions=9)。
  /// 拖动中只更新草稿并即时显示数值,松手才提交到服务
  Widget _buildListMaxSection(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最多显示', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${_featuredDraft.round()} 条',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _featuredDraft,
            min: SettingsService.featuredMin.toDouble(),
            max: SettingsService.featuredMax.toDouble(),
            divisions: 9,
            label: '${_featuredDraft.round()} 条',
            onChanged: (v) => setState(() => _featuredDraft = v),
            onChangeEnd: (v) =>
                SettingsService.instance.setFeaturedMax(v.round()),
          ),
        ],
      ),
    );
  }

  /// 渲染方法
  Widget _buildRenderType(BuildContext context, SettingsService s) {
    final theme = Theme.of(context);

    // 转换为 DropdownMenuItem 列表
    final dropdownItems = _renderType.map<DropdownMenuItem<String>>((item) {
      final (label, value) = item;
      return DropdownMenuItem<String>(value: value, child: Text(label));
    }).toList();

    final selectedValue = SettingsService.renderTypes.contains(s.renderType)
        ? s.renderType
        : 'default';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text('渲染方法', style: theme.textTheme.bodyMedium),
          Spacer(),
          // 使用下拉框
          DropdownButton<String>(
            value: selectedValue,
            items: dropdownItems,
            onChanged: (String? newValue) {
              if (newValue != null) {
                SettingsService.instance.setRenderType(newValue);
              }
            },
            // 样式定制（可选）
            style: theme.textTheme.bodyMedium,
            // 设置为透明下划线
            underline: Container(height: 0, color: Colors.transparent),
            icon: Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
            // 如果希望下拉框宽度自适应内容
            isDense: false,
            // 禁用焦点和悬停效果
            focusColor: Colors.transparent,
          ),
        ],
      ),
    );
  }
}
