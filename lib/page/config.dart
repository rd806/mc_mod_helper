import 'package:flutter/material.dart';

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
    late double _featuredDraft = SettingsService.instance.featuredMax.toDouble();

    /// 字体缩放滑条草稿值(独立于推荐条数草稿)
    late double _fontScaleDraft = SettingsService.instance.fontScale
        .clamp(SettingsService.fontMin, SettingsService.fontMax);

    /// 系统主题
    static const List<(String, ThemeMode)> _themeMode = [
        ('跟随系统', ThemeMode.system),
        ('亮色', ThemeMode.light),
        ('暗色', ThemeMode.dark)
    ];

    /// 可选强调色：名称 + 色值
    static const List<(String, Color)> _seedColors = [
        ('蓝色', Colors.blue),
        ('绿色', Colors.green),
        ('紫色', Colors.deepPurple),
        ('橙色', Colors.orange),
        ('红色', Colors.red)
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
                            _sectionTitle(context, '主题选择'),
                            _buildThemeModeSection(s),
                            _sectionTitle(context, '颜色种子'),
                            _buildSeedColorSection(context, s),
                            _sectionTitle(context, '字体设置'),
                            _buildFontScaleSection(context, s),
                            _sectionTitle(context, '首页设置'),
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
    Widget _buildThemeModeSection(SettingsService s) {
        final theme = s.themeMode;
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
                segments: [
                    for (final (label, value) in _themeMode)
                        ButtonSegment(value: value, label: Text(label)),
                ],
                // 防御:存档值不在三档内(被外部改动)时回落显示“跟随系统”,
                // SegmentedButton 要求 selected 是 segments 的子集,否则断言崩溃
                selected: {
                    _themeMode.any((f) => f.$2 == theme) ? theme : ThemeMode.system,
                },
                showSelectedIcon: false,
                onSelectionChanged: (selection) => SettingsService.instance.setThemeMode(selection.first),
            ),
        );
    }

    /// 强调色:一行色块,选中项画外圈 + 对勾
    Widget _buildSeedColorSection(BuildContext context, SettingsService s) {
        final theme = Theme.of(context);
        final selectedArgb = s.seedColor.toARGB32();
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
                children: [
                    for (final (label, color) in _seedColors)
                        _buildColor(label, color, selectedArgb, theme),
                ],
            ),
        );
    }

    // 颜色按钮
    Widget _buildColor(String label, Color color, int selectedArgb, ThemeData theme) {
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
                                color: selectedArgb == color.toARGB32() ? theme.colorScheme.onSurface : Colors.transparent,
                                width: 2,
                            ),
                        ),
                        child: selectedArgb == color.toARGB32() ? Icon(
                            Icons.check,
                            size: 20,
                            // 按色块明暗选白/黑对勾
                            color: ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark ? Colors.white : Colors.black87,
                        ) : null,
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

    /// 推荐列表来源(最新收录/最新编辑),修改后持久化,主页监听变化自动重拉
    Widget _buildListSource(BuildContext context, SettingsService s) {
        final theme = Theme.of(context);
        return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Row(
                children: [
                    Text(
                        '推荐来源', style: theme.textTheme.bodyMedium
                    ),
                    Spacer(),
                    SegmentedButton<String>(
                        segments: const [
                            ButtonSegment(value: '', label: Text('默认')),
                            ButtonSegment(value: 'createtime', label: Text('最新收录')),
                            ButtonSegment(value: 'lastedittime', label: Text('最新编辑')),
                        ],
                        // 防御:存档值不在选项内时回落显示“最新收录”,
                        // SegmentedButton 要求 selected 是 segments 的子集
                        selected: {
                            SettingsService.featuredSources.contains(s.featuredSource)
                                ? s.featuredSource : 'createtime',
                        },
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (selection) => SettingsService.instance
                            .setFeaturedSource(selection.first),
                    )
                ],
            )
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
                        max: SettingsService.featuredMaxLimit.toDouble(),
                        divisions: 9,
                        label: '${_featuredDraft.round()} 条',
                        onChanged: (v) => setState(() => _featuredDraft = v),
                        onChangeEnd: (v) => SettingsService.instance.setFeaturedMax(v.round()),
                    ),
                ],
            ),
        );
    }
}
