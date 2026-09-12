import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:mc_mod_helper/render/default_render/html_content.dart';
import 'package:mc_mod_helper/render/hyper_render/hyper.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/service/value/render.dart';

import '../../../service/agent/translate.dart';
import '../../../model/mod/mod_detail.dart';
import '../../../setting/display_settings.dart';
import '../intro/section_title.dart';

/// 模组介绍:渲染清洗后的 HTML 正文(两种来源的描述都是清洗后的 HTML)。
///
/// 按设置里的渲染方法二选一:
/// - default:自写 HtmlContent(逐标签映射控件,正文零 MouseRegion)
/// - hyperViewer:hyper_render(单 RenderObject 布局引擎,性能更优)
///
/// 标题行右侧提供「翻译/原文」按钮:由用户手动决定是否用 AI 翻译正文
/// (译文按 模组+语言 缓存在会话内,再次切换不再重复请求)。
class DescriptionCard extends StatefulWidget {
  const DescriptionCard({
    super.key,
    required this.mod,
    required this.onLinkTap,
  });

  final ModDetail mod;

  /// 正文链接/图片点击回调(灯箱/站内跳转/浏览器由调用方分流)
  final void Function(String url) onLinkTap;

  @override
  State<DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<DescriptionCard> {
  /// 是否展示译文
  bool _showTranslated = false;

  /// 正在请求翻译
  bool _loading = false;

  /// 分块翻译进度(总块数 > 1 时按钮显示 已完成/总数)
  int _chunkDone = 0;
  int _chunkTotal = 0;

  /// 当前译文及其目标语言(语言变化时视为失效,回到原文)
  String? _translatedHtml;
  String? _translatedLang;

  /// 缓存/请求用的键:区分来源与模组
  String get _cacheKey => '${widget.mod.source.name}:${widget.mod.id}';

  /// 当前应渲染的正文
  String get _html {
    final lang = LanguageSettings.instance.translateLang;
    if (_showTranslated && _translatedHtml != null && _translatedLang == lang) {
      return _translatedHtml!;
    }
    return widget.mod.body!;
  }

  /// 译文当前是否生效(按钮文案/状态据此判断)
  bool get _translatedActive =>
      _showTranslated &&
      _translatedHtml != null &&
      _translatedLang == LanguageSettings.instance.translateLang;

  Future<void> _toggleTranslate() async {
    if (_loading) return;
    final lang = LanguageSettings.instance.translateLang;
    // 已有该语言译文:直接切换原文/译文,不再请求
    final cached = _translatedHtml != null && _translatedLang == lang
        ? _translatedHtml
        : TranslateApi.cachedHtml(_cacheKey, targetLang: lang);
    if (cached != null) {
      setState(() {
        _translatedHtml = cached;
        _translatedLang = lang;
        _showTranslated = !_translatedActive;
      });
      return;
    }
    if (!AgentSettings.instance.configured) {
      _showMessage('尚未配置 AI 接口 Key,请到「设置 → AI 设置」填写');
      return;
    }
    setState(() {
      _loading = true;
      _chunkDone = 0;
      _chunkTotal = 0;
    });
    try {
      final html = await TranslateApi.translateHtml(
        widget.mod.body!,
        cacheKey: _cacheKey,
        // 长正文分块翻译,进度反馈到按钮(翻译中 2/5)
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _chunkDone = done;
            _chunkTotal = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _translatedHtml = html;
        _translatedLang = lang;
        _showTranslated = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('$e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mod.body == null || widget.mod.body!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: DetailSectionTitle(
                    title: '模组介绍',
                    icon: Icons.article_rounded,
                  ),
                ),
                _buildTranslateButton(context),
              ],
            ),
            _buildHTML(context),
          ],
        ),
      ),
    );
  }

  /// 翻译/原文切换按钮(加载中转圈,未配置密钥时点击给出引导)
  Widget _buildTranslateButton(BuildContext context) {
    final theme = Theme.of(context);
    final langLabel = LanguageSettings.instance.translateLangLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Tooltip(
        message: _translatedActive ? '显示原文' : '翻译为$langLabel',
        child: TextButton.icon(
          onPressed: _toggleTranslate,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.translate, size: 18),
          label: Text(
            _loading
                ? (_chunkTotal > 1 ? '翻译中 $_chunkDone/$_chunkTotal' : '翻译中…')
                : (_translatedActive ? '原文' : '翻译'),
            style: theme.textTheme.labelLarge,
          ),
        ),
      ),
    );
  }

  /// 按渲染方法选择正文渲染器
  Widget _buildHTML(BuildContext context) {
    final theme = Theme.of(context);
    RenderType type = DisplaySettings.instance.renderType;
    switch (type) {
      case RenderType.auto:
        return HtmlContent(
          html: _html,
          textStyle: theme.textTheme.bodyMedium,
          onLinkTap: widget.onLinkTap,
        );
      case RenderType.hyper:
        return _mouseDraggable(
          context,
          HyperViewer(
            html: _html,
            mode: HyperRenderMode.sync,
            shrinkWrap: true,
            selectable: false,
            customCss: HyperRender.hyperCss(theme),
            onLinkTap: widget.onLinkTap,
          ),
        );
    }
  }

  /// 桌面端 ScrollBehavior 默认只认触摸/手写笔拖拽,鼠标拖不动
  /// 正文里表格的横向滚动容器;包一层开启鼠标/触控板拖拽的配置
  /// (只作用于描述内容,不影响外层列表的既有滚动方式)
  Widget _mouseDraggable(BuildContext context, Widget widget) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.invertedStylus,
        },
      ),
      child: widget,
    );
  }
}
