import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:mc_mod_helper/render/default_render/html_content.dart';
import 'package:mc_mod_helper/render/hyper_render/hyper.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:mc_mod_helper/setting/language_settings.dart';
import 'package:mc_mod_helper/setting/value/render.dart';

import '../../service/agent/translate.dart';
import '../../model/project/project_detail.dart';
import '../../setting/display_settings.dart';
import '../common/section_title.dart';

/// 模组介绍:渲染清洗后的 HTML 正文(两种来源的描述都是清洗后的 HTML)。
///
/// 按设置里的渲染方法二选一:
/// - default:自写 HtmlContent(逐标签映射控件,正文零 MouseRegion)
/// - hyperViewer:hyper_render(单 RenderObject 布局引擎,性能更优)
///
/// 标题行右侧提供「翻译/原文」按钮:由用户手动决定是否用 AI 翻译正文
/// (译文按 模组+语言 缓存在会话内,再次切换不再重复请求)。
///
/// 设置里打开「自动翻译」后,本卡片会在挂载时自行发起翻译,不再需要点按钮:
/// 未配置 AI Key 时静默用原文,失败则在标题行下方给一条可点重试的提示。
class DescriptionCard extends StatefulWidget {
  const DescriptionCard({
    super.key,
    required this.mod,
    required this.onLinkTap,
  });

  final ProjectDetail mod;

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

  /// 自动翻译失败的原因(行内提示;手动失败仍走 SnackBar)
  String? _autoError;

  /// 已经为哪个目标语言自动发起过请求。
  ///
  /// 失败后不再自动重试(否则一进页面就对着坏 Key 反复请求),由用户点
  /// 「重试」;也用于避免开关/Key 的无关变化再次触发同一篇正文的翻译。
  String? _autoStartedFor;

  /// 用户在自动模式下手动切回了原文(否决自动翻译)。
  ///
  /// 不记这个标记的话,任何一次设置通知(哪怕只是改了模型名)都会把用户
  /// 主动选择的原文顶回译文;只有「重新打开开关」或「换了目标语言」才算
  /// 新的意图,那时才清除。
  bool _autoSuppressed = false;

  /// 上次判定时见到的开关与目标语言,用来识别"设置真的变了"
  bool _seenAuto = false;
  String? _seenLang;

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

  @override
  void initState() {
    super.initState();
    // 开关、目标语言变化要跟着变;Key 可能是用户刚去设置页填上的
    LanguageSettings.instance.addListener(_onSettingsChanged);
    AgentSettings.instance.addListener(_onSettingsChanged);
    // 首帧后再判定:翻译一旦命中缓存会同步 setState,不能在 initState 里做
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _considerAutoTranslate(),
    );
  }

  @override
  void didUpdateWidget(DescriptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 详情页刷新/换模组时 element 相同、State 会被复用,不重置就会把上一个
    // 模组的译文渲染到新模组的正文位置上
    if (_cacheKey == '${oldWidget.mod.source.name}:${oldWidget.mod.id}') return;
    _translatedHtml = null;
    _translatedLang = null;
    _autoStartedFor = null;
    _autoSuppressed = false;
    _autoError = null;
    _showTranslated = false;
    _loading = false;
    // 此刻正处于构建阶段,不能同步 setState:推到帧后再判定
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _considerAutoTranslate(),
    );
  }

  @override
  void dispose() {
    LanguageSettings.instance.removeListener(_onSettingsChanged);
    AgentSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // 无条件重建:目标语言变化后,按钮提示与"当前译文是否仍有效"都要重算
    setState(() {});
    _considerAutoTranslate();
  }

  /// 自动翻译的判定入口:开关、目标语言、AI 配置任一变化都走这里。
  ///
  /// 保证幂等 —— 没有新情况时什么都不做,用户手动切到「原文」也不会被
  /// 无关的设置变化拉回译文。
  Future<void> _considerAutoTranslate() async {
    final settings = LanguageSettings.instance;
    final lang = settings.translateLang;
    // 只有"设置真的变了"才解除用户的否决:同一个开关的重复通知不该把用户
    // 主动选的「原文」顶掉,而重开开关 / 换语言都是新的意图
    if (settings.autoTranslate != _seenAuto || lang != _seenLang) {
      _autoSuppressed = false;
    }
    _seenAuto = settings.autoTranslate;
    _seenLang = lang;

    // 开关关掉:回原文(译文留在 State 里,再打开可立即切回,不重新请求)
    if (!settings.autoTranslate) {
      if (_showTranslated && mounted) {
        setState(() => _showTranslated = false);
      }
      return;
    }
    if (_autoSuppressed || _loading) return;
    // 正文可能为空(此时整卡都不渲染),不能让下面的 ! 崩掉
    final body = widget.mod.body;
    if (body == null || body.isEmpty) return;
    // 已有该语言译文(本页刚翻的,或会话内缓存的别的页面翻的):直接切过去
    final ready =
        (_translatedLang == lang ? _translatedHtml : null) ??
        TranslateApi.cachedHtml(_cacheKey, targetLang: lang);
    if (ready != null) {
      if (!mounted) return;
      setState(() {
        _translatedHtml = ready;
        _translatedLang = lang;
        _showTranslated = true;
        _autoError = null;
      });
      return;
    }
    if (_autoStartedFor == lang) return;
    // 未配置 Key:安静地用原文,不弹提示(用户没主动操作);
    // 手动按钮仍在,点了才给「去设置页填写」的引导
    if (!AgentSettings.instance.configured) return;
    // 正文本来就是目标语言:翻一遍纯属白花 token(仅拦自动,手动照翻)
    if (TranslateApi.alreadyInTargetLang(body, lang)) return;
    _autoStartedFor = lang;
    await _translate(lang, auto: true);
  }

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
        // 切回原文 = 否决自动翻译;切到译文 = 用户明确要译文,解除否决
        _autoSuppressed = !_showTranslated;
        _autoError = null;
      });
      return;
    }
    if (!AgentSettings.instance.configured) {
      _showMessage('尚未配置 AI 接口 Key,请到「设置 → AI 设置」填写');
      return;
    }
    _autoSuppressed = false;
    await _translate(lang);
  }

  /// 发起翻译。[auto] 为 true 表示由自动翻译触发 —— 失败时写进行内提示,
  /// 而不是弹一个用户没主动操作就冒出来的 SnackBar。
  Future<void> _translate(String lang, {bool auto = false}) async {
    if (_loading) return;
    final previous = _autoError;
    // 记下发起时的模组:请求返回时若已换模组,结果必须丢弃
    final key = _cacheKey;
    setState(() {
      _loading = true;
      _chunkDone = 0;
      _chunkTotal = 0;
      _autoError = null;
    });
    try {
      final html = await TranslateApi.translateHtml(
        widget.mod.body!,
        cacheKey: key,
        targetLang: lang,
        // 长正文分块翻译,进度反馈到按钮(翻译中 2/5)
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _chunkDone = done;
            _chunkTotal = total;
          });
        },
      );
      if (!mounted || key != _cacheKey) return;
      setState(() {
        _translatedHtml = html;
        _translatedLang = lang;
        _showTranslated = true;
        _loading = false;
        _autoError = null;
      });
      // 请求期间目标语言又变了:本次结果按语言已失效,补一次判定
      if (LanguageSettings.instance.translateLang != lang) {
        await _considerAutoTranslate();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _autoError = auto ? '$e' : previous;
      });
      if (!auto) _showMessage('$e');
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
            SectionTitle(
              title: '模组介绍',
              icon: Icons.article_rounded,
              children: [_buildTranslateButton(context)],
            ),
            if (_autoError != null && !_translatedActive)
              _buildAutoError(context),
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
    return Tooltip(
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
    );
  }

  /// 自动翻译失败的提示条。
  ///
  /// 不用 SnackBar:自动路径是用户没主动操作的,而且用户很可能正待在设置页
  /// 填 Key(详情页此时仍活着),弹窗会落在与当前操作无关的页面上。
  Widget _buildAutoError(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '自动翻译失败：$_autoError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () => _translate(
                    LanguageSettings.instance.translateLang,
                    auto: true,
                  ),
            child: const Text('重试'),
          ),
        ],
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
