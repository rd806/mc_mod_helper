import 'package:flutter/material.dart';

import '../services/settings.dart';

/// 设置页:主题(模式/强调色)、字体大小、推荐列表条数上限
class ConfigPage extends StatefulWidget {
    const ConfigPage({super.key});

    @override
    State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
    /// 滑条草稿值:拖动过程中只改草稿,松手(onChangeEnd)才提交,
    /// 避免每个档位变化都触发主页重新拉取(多页抓取耗时较长)
    late double _featuredDraft =
        SettingsService.instance.featuredMax.toDouble();

    /// 可选强调色:名称 + 色值
    static const List<(String, Color)> _seedColors = [
        ('蓝色', Colors.blue),
        ('绿色', Colors.green),
        ('紫色', Colors.deepPurple),
        ('橙色', Colors.orange),
    ];

    /// 可选字体缩放:标签 + 倍率
    static const List<(String, double)> _fontScales = [
        ('小', 0.9),
        ('标准', 1.0),
        ('大', 1.15),
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
                            _sectionTitle(context, '字体大小'),
                            _buildFontScaleSection(context, s),
                            _sectionTitle(context, '推荐列表'),
                            _buildFeaturedMaxSection(context, s),
                        ],
                    );
                },
            ),
        );
    }

    Widget _sectionTitle(BuildContext context, String title) {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        );
    }

    /// 主题模式:跟随系统 / 亮色 / 暗色。
    /// 用 RadioGroup 管理整组选中值(RadioListTile 的
    /// groupValue/onChanged 在 3.32+ 已废弃)
    Widget _buildThemeModeSection(SettingsService s) {
        return RadioGroup<ThemeMode>(
            groupValue: s.themeMode,
            onChanged: (mode) {
                if (mode != null) SettingsService.instance.setThemeMode(mode);
            },
            child: const Column(
                children: [
                    RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: Text('跟随系统'),
                    ),
                    RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: Text('亮色'),
                    ),
                    RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: Text('暗色'),
                    ),
                ],
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
                        Padding(
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
                                        // 按色块明暗选白/黑对勾,保证可读
                                        color: ThemeData.estimateBrightnessForColor(
                                                color) ==
                                            Brightness.dark
                                            ? Colors.white
                                            : Colors.black87,
                                        )
                                    : null,
                                ),
                            ),
                        ),
                    ),
                ],
            ),
        );
    }

    /// 字体大小三档:小 0.9 / 标准 1.0 / 大 1.15
    Widget _buildFontScaleSection(BuildContext context, SettingsService s) {
        final scale = s.fontScale;
        return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<double>(
            segments: [
            for (final (label, value) in _fontScales)
                ButtonSegment(value: value, label: Text(label)),
            ],
            // 防御:存档值不在三档内(被外部改动)时回落显示“标准”,
            // SegmentedButton 要求 selected 是 segments 的子集,否则断言崩溃
            selected: {
            _fontScales.any((f) => f.$2 == scale) ? scale : 1.0,
            },
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
            SettingsService.instance.setFontScale(selection.first),
        ),
        );
    }

    /// 推荐列表条数上限:滑条 5–50,步进 5(divisions=9)。
    /// 拖动中只更新草稿并即时显示数值,松手才提交到服务
    Widget _buildFeaturedMaxSection(BuildContext context, SettingsService s) {
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
                onChangeEnd: (v) =>
                SettingsService.instance.setFeaturedMax(v.round()),
            ),
            ],
        ),
        );
    }
}
