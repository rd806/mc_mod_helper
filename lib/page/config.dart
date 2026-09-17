import 'package:flutter/material.dart';
import 'package:mc_mod_helper/icon/icon_manager.dart';
import 'package:mc_mod_helper/setting/value/render.dart';
import 'package:mc_mod_helper/setting/value/display.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/widget/button/color_box.dart';
import 'package:mc_mod_helper/widget/button/dropdown_box.dart';
import 'package:mc_mod_helper/widget/button/input_box.dart';
import 'package:mc_mod_helper/widget/button/switch_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../setting/agent_settings.dart';
import '../setting/theme_settings.dart';
import '../widget/common/expansion_tile.dart';

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

  static const List<(String, String)> _fontTypes = [
    ('系统字体', ThemeSettings.systemFont),
    ('HarmonyOS Sans', 'HarmonyOS_Sans'),
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
        children: [
          _buildIcon(theme),
          ListenableBuilder(
            listenable: ThemeSettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.light_mode_rounded,
              title: '主题',
              children: [
                _buildThemeMode(ThemeSettings.instance),
                _buildSeedColor(ThemeSettings.instance),
                _buildFontType(ThemeSettings.instance),
                _buildFontScale(context, ThemeSettings.instance),
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
                _buildDataSource(DisplaySettings.instance),
                _buildDisplayStyle(DisplaySettings.instance),
              ],
            ),
          ),

          ListenableBuilder(
            listenable: LanguageSettings.instance,
            builder: (context, _) => SettingsGroup(
              icon: Icons.language_rounded,
              title: '语言',
              children: [
                _buildTranslateLang(LanguageSettings.instance),
                _buildAutoTranslate(LanguageSettings.instance),
              ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/launcher/app_icon.png',
            width: 100, // 设置宽度
            height: 100, // 设置高度
            fit: BoxFit.cover, // 设置图片的填充模式
          ),
          Text(
            'MC Mod Helper',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text('简易的Minecraft模组浏览器', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
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
  Widget _buildThemeMode(ThemeSettings s) {
    return DropdownBox<ThemeMode>(
      title: '主题选择',
      value: s.themeMode,
      options: [
        for (final (label, mode) in _themeMode)
          DropdownOption(
            label,
            mode,
            icon: IconManager.getIconForThemeMode(mode),
          ),
      ],
      onChanged: ThemeSettings.instance.setThemeMode,
    );
  }

  /// 强调色(种子色):行内是圆形色块 + 当前色号,点击弹窗输入十六进制
  Widget _buildSeedColor(ThemeSettings s) {
    return ColorBox(
      title: '颜色种子',
      value: s.seedColor,
      onSaved: (color) => ThemeSettings.instance.setSeedColor(color.toARGB32()),
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
          DropdownOption(
            label,
            font,
            // 系统字体(哨兵值 'system')不是真实字体族,置空用默认字体渲染
            textStyle: TextStyle(
              fontFamily: font == ThemeSettings.systemFont ? null : font,
            ),
          ),
      ],
      onChanged: ThemeSettings.instance.setFontType,
    );
  }

  /// 字体大小滑块
  Widget _buildFontScale(BuildContext context, ThemeSettings s) {
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
  Widget _buildDataSource(DisplaySettings s) {
    return DropdownBox<ModSource>(
      title: '数据来源',
      value: s.dataSource,
      options: [
        for (final (label, source) in _modSource)
          DropdownOption(
            label,
            source,
            icon: IconManager.getIconForDataSource(source),
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
            icon: IconManager.getIconForDisplayStyle(style),
          ),
      ],
      onChanged: DisplaySettings.instance.setDisplayStyle,
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

  /// 自动翻译开关
  Widget _buildAutoTranslate(LanguageSettings s) {
    return SwitchTile(
      title: '自动翻译',
      subtitle: '打开模组详情页时自动翻译正文',
      initialValue: s.autoTranslate,
      onChanged: LanguageSettings.instance.setAutoTranslate,
    );
  }
}
