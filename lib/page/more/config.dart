import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/render.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/widget/common/dropdown_box.dart';
import 'package:mc_mod_helper/widget/handler/input_box.dart';
import 'package:mc_mod_helper/icon/link_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../setting/agent_settings.dart';
import '../../setting/theme_settings.dart';
import '../../widget/common/expansion_tile.dart';

/// 设置页:主题(模式/强调色)、字体大小、推荐列表条数上限
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  /// 字体缩放滑条草稿值(独立于推荐条数草稿)
  late double _fontScaleDraft = ThemeSettings.instance.fontScale.clamp(
    ThemeSettings.fontMin,
    ThemeSettings.fontMax,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        children: [
          _buildIcon(theme),
          ListenableBuilder(
            listenable: ThemeSettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.light_mode_rounded,
              title: '主题',
              children: [
                _buildThemeModeSection(ThemeSettings.instance),
                _buildSeedColorSection(theme, ThemeSettings.instance),
                _buildFontType(ThemeSettings.instance),
                _buildFontScaleSection(context, ThemeSettings.instance),
              ],
            ),
          ),

          ListenableBuilder(
            listenable: DisplaySettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.display_settings,
              title: '显示',
              children: [
                _buildRenderType(DisplaySettings.instance),
                _buildDataSourceSection(DisplaySettings.instance),
                _buildDisplayStyle(DisplaySettings.instance),
              ],
            ),
          ),

          ListenableBuilder(
            listenable: LanguageSettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.language_rounded,
              title: '语言',
              children: [_buildTranslateLang(LanguageSettings.instance)],
            ),
          ),

          ListenableBuilder(
            listenable: AgentSettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.smart_toy_outlined,
              title: 'AI',
              children: [
                _buildAgentBaseUrl(AgentSettings.instance),
                _buildAgentApiKey(AgentSettings.instance),
                _buildAgentModel(AgentSettings.instance),
              ],
            ),
          ),

          SettingsGroup(
            icon: Icons.info_outline_rounded,
            title: '关于',
            children: [
              _buildLink(
                '开源协议',
                'GPL-3.0',
                'https://github.com/rd806/mc_mod_helper/blob/main/LICENSE',
              ),
              _buildLink(
                '项目地址',
                '点击打开',
                'https://github.com/rd806/mc_mod_helper',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 项目封面
  Widget _buildIcon(ThemeData theme) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/app_icon.png',
            width: 100, // 设置宽度
            height: 100, // 设置高度
            fit: BoxFit.cover, // 设置图片的填充模式
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                'MC Mod Helper',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text('简易的Minecraft模组浏览器', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建链接
  Widget _buildLink(String title, String label, String url) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text(title),
          const Spacer(),
          ActionChip(
            label: Text(label),
            onPressed: () {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }

  /// 主题模式；跟随系统 / 亮色 / 暗色。
  Widget _buildThemeModeSection(ThemeSettings s) {
    return DropdownBox<ThemeMode>(
      title: '主题选择',
      value: s.themeMode,
      options: [
        for (final (label, mode) in _themeMode)
          DropdownOption(label, mode, icon: Icon(_getIconForThemeMode(mode))),
      ],
      onChanged: ThemeSettings.instance.setThemeMode,
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
  Widget _buildSeedColorSection(ThemeData theme, ThemeSettings s) {
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
          onTap: () => ThemeSettings.instance.setSeedColor(color),
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
  Widget _buildRenderType(DisplaySettings s) {
    return DropdownBox<RenderType>(
      title: '渲染方法',
      value: s.renderType,
      options: [
        for (final (label, type) in _renderType) DropdownOption(label, type),
      ],
      onChanged: DisplaySettings.instance.setRenderType,
    );
  }

  /// 字体选择(选项与选中值都用该字体渲染,便于预览)
  Widget _buildFontType(ThemeSettings s) {
    return DropdownBox<String>(
      title: '字体选择',
      value: s.fontType,
      options: [
        for (final (label, font) in _fontTypes)
          DropdownOption(label, font, textStyle: TextStyle(fontFamily: font)),
      ],
      onChanged: ThemeSettings.instance.setFontType,
    );
  }

  /// 字体大小滑块
  Widget _buildFontScaleSection(BuildContext context, ThemeSettings s) {
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
            min: ThemeSettings.fontMin,
            max: ThemeSettings.fontMax,
            divisions: 15, // 步进 0.1,刻度包含默认值 1.0
            label: '${_fontScaleDraft.toStringAsFixed(2)}×',
            onChanged: (v) => setState(() => _fontScaleDraft = v),
            onChangeEnd: (v) => ThemeSettings.instance.setFontScale(v),
          ),
        ],
      ),
    );
  }

  /// 搜索/详情数据来源(MC百科/Modrinth),修改后持久化
  Widget _buildDataSourceSection(DisplaySettings s) {
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
      onChanged: DisplaySettings.instance.setDataSource,
    );
  }

  /// 模组信息展示方式(网格/列表/自适应),修改后持久化,
  /// 首页推荐/分类/收藏页监听变化即时切换布局
  Widget _buildDisplayStyle(DisplaySettings s) {
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
      onChanged: DisplaySettings.instance.setDisplayStyle,
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
  Widget _buildTranslateLang(LanguageSettings s) {
    return DropdownBox<String>(
      title: '目标语言',
      value: s.translateLang,
      fallback: LanguageSettings.defaultTranslateLang,
      options: [
        for (final (label, code) in LanguageSettings.translateLanguages)
          DropdownOption(label, code),
      ],
      onChanged: LanguageSettings.instance.setTranslateLang,
    );
  }
}
