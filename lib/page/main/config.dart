import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/render.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/widget/common/dropdown_box.dart';
import 'package:mc_mod_helper/widget/handler/input_box.dart';
import 'package:mc_mod_helper/widget/common/link_icons.dart';

import '../../setting/agent_settings.dart';
import '../../setting/settings.dart';

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

  static const List<(String, String)> _fontTypes = [
    ('思源黑体', 'NotoSansSC'),
    ('Unifont', 'Unifont'),
  ];

  // 推荐方法
  // 与 settings 中的一致(语义对应 mcmod 列表页 sort 参数:
  // createtime=最新收录,lastedittime=最新编辑)
  static const List<(String, FeatureSource)> _sortMethod = [
    ('默认', FeatureSource.none),
    ('最新收录', FeatureSource.createTime),
    ('最新编辑', FeatureSource.lastEditTime),
  ];

  static const List<(String, DisplayStyle)> _displayStyle = [
    ('网格', DisplayStyle.card),
    ('列表', DisplayStyle.table),
    ('自适应', DisplayStyle.auto),
  ];

  static const List<(String, RenderType)> _renderType = [
    ('默认', RenderType.auto),
    ('Hyper', RenderType.hyper),
  ];

  static const List<(String, ModSource)> _modSource = [
    ('MC百科', ModSource.mcmod),
    ('Modrinth', ModSource.modrinth),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              _sectionTitle(theme, '主题设置'),
              _buildThemeModeSection(s),
              _buildSeedColorSection(theme, s),
              _buildRenderType(s),
              _sectionTitle(theme, '字体设置'),
              _buildFontType(s),
              _buildFontScaleSection(context, s),
              _sectionTitle(theme, '数据设置'),
              _buildDataSourceSection(s),
              _buildListSource(s),
              _buildListMaxSection(theme, s),
              _buildDisplayStyle(s),
              _buildTranslateLang(s),
              // 翻译与模组助手共用同一套 AI 接口配置;三项都是弹窗输入,
              // 保存后要跟着服务值刷新行内展示,故包一层监听
              _sectionTitle(theme, 'AI 设置'),
              ListenableBuilder(
                listenable: AgentSettings.instance,
                builder: (context, _) => Column(
                  children: [
                    _buildAgentBaseUrl(AgentSettings.instance),
                    _buildAgentApiKey(AgentSettings.instance),
                    _buildAgentModel(AgentSettings.instance),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 配置项标题
  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  /// 主题模式；跟随系统 / 亮色 / 暗色。
  Widget _buildThemeModeSection(SettingsService s) {
    return DropdownBox<ThemeMode>(
      title: '主题选择',
      value: s.themeMode,
      options: [
        for (final (label, mode) in _themeMode)
          DropdownOption(label, mode, icon: Icon(_getIconForThemeMode(mode))),
      ],
      onChanged: SettingsService.instance.setThemeMode,
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
  Widget _buildSeedColorSection(ThemeData theme, SettingsService s) {
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

  /// 渲染方法
  Widget _buildRenderType(SettingsService s) {
    return DropdownBox<RenderType>(
      title: '渲染方法',
      value: s.renderType,
      options: [
        for (final (label, type) in _renderType) DropdownOption(label, type),
      ],
      onChanged: SettingsService.instance.setRenderType,
    );
  }

  /// 字体选择(选项与选中值都用该字体渲染,便于预览)
  Widget _buildFontType(SettingsService s) {
    return DropdownBox<String>(
      title: '字体选择',
      value: s.fontType,
      options: [
        for (final (label, font) in _fontTypes)
          DropdownOption(label, font, textStyle: TextStyle(fontFamily: font)),
      ],
      onChanged: SettingsService.instance.setFontType,
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
  Widget _buildDataSourceSection(SettingsService s) {
    return DropdownBox<ModSource>(
      title: '数据来源',
      value: s.dataSource,
      options: [
        for (final (label, source) in _modSource)
          DropdownOption(
            label,
            source,
            icon: LinkIcons.getIconForDataSource(source),
          ),
      ],
      onChanged: SettingsService.instance.setDataSource,
    );
  }

  /// 推荐列表来源(最新收录/最新编辑),修改后持久化,主页监听变化自动重拉
  Widget _buildListSource(SettingsService s) {
    return DropdownBox<FeatureSource>(
      title: '推荐来源',
      value: s.featuredSource,
      options: [
        for (final (label, source) in _sortMethod)
          DropdownOption(label, source),
      ],
      onChanged: SettingsService.instance.setFeaturedSource,
    );
  }

  /// 模组信息展示方式(网格/列表/自适应),修改后持久化,
  /// 首页推荐/分类/收藏页监听变化即时切换布局
  Widget _buildDisplayStyle(SettingsService s) {
    return DropdownBox<DisplayStyle>(
      title: '展示方式',
      value: s.displayStyle,
      // 回退值是「列表」而不是第一项「网格」(设置服务已校验,
      // 这里只是存储值异常时的兜底)
      fallback: DisplayStyle.table,
      options: [
        for (final (label, style) in _displayStyle)
          DropdownOption(
            label,
            style,
            icon: Icon(_getIconForDisplayStyle(style)),
          ),
      ],
      onChanged: SettingsService.instance.setDisplayStyle,
    );
  }

  /// 获取图标
  IconData _getIconForDisplayStyle(DisplayStyle style) {
    switch (style) {
      case DisplayStyle.card:
        return Icons.view_module_rounded;
      case DisplayStyle.table:
        return Icons.table_rows_rounded;
      case DisplayStyle.auto:
        return Icons.hdr_auto_rounded;
    }
  }

  /// 推荐列表条数上限:滑条 5–50,步进 5(divisions=9)。
  /// 拖动中只更新草稿并即时显示数值,松手才提交到服务
  Widget _buildListMaxSection(ThemeData theme, SettingsService s) {
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

  /// AI 接口地址(OpenAI 兼容,如 https://api.openai.com/v1)
  Widget _buildAgentBaseUrl(AgentSettings a) {
    return InputBox(
      title: '接口地址',
      value: a.baseUrl,
      hint: AgentSettings.defaultBaseUrl,
      onSaved: a.setBaseUrl,
    );
  }

  /// AI 接口 Key(用户自行填写;留空则翻译/助手给出引导)
  Widget _buildAgentApiKey(AgentSettings a) {
    return InputBox(
      title: 'API Key',
      value: a.apiKey,
      hint: '未配置',
      obscure: true,
      onSaved: a.setApiKey,
    );
  }

  /// AI 模型名
  Widget _buildAgentModel(AgentSettings a) {
    return InputBox(
      title: '模型',
      value: a.model,
      hint: AgentSettings.defaultModel,
      onSaved: a.setModel,
    );
  }

  /// 翻译目标语言(详情页翻译按钮使用该语言)
  Widget _buildTranslateLang(SettingsService s) {
    return DropdownBox<String>(
      title: '目标语言',
      value: s.translateLang,
      fallback: SettingsService.defaultTranslateLang,
      options: [
        for (final (label, code) in SettingsService.translateLangs)
          DropdownOption(label, code),
      ],
      onChanged: SettingsService.instance.setTranslateLang,
    );
  }
}
