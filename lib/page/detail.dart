import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:mc_mod_helper/api/source.dart';
import 'package:mc_mod_helper/service/settings.dart';
import 'package:mc_mod_helper/widget/description/cover.dart';
import 'package:mc_mod_helper/widget/link_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/mod_detail.dart';
import '../render/html_content.dart';
import '../widget/description/collapsible_chips.dart';
import '../widget/description/image_box.dart';

/// 模组详情页
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.id,
    this.initialTitle,
    this.initialDescription,
    this.source = ModSource.mcmod,
  });

  /// 统一模组标识(字符串):MC百科为数字字符串(如 '123'),Modrinth 为 slug(如 'jei')
  final String id;

  /// 数据来源:'mcmod' 或 'modrinth',决定用哪个 API 加载详情
  final ModSource source;

  /// 详情加载完成前显示在标题栏的名称
  final String? initialTitle;

  /// 详情页没有“概述”时回退显示的简介(来自搜索结果)
  final String? initialDescription;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<ModDetail> _future;

  // 左右控制器
  final ScrollController _leftController = ScrollController();
  final ScrollController _rightController = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    // 释放资源，防止内存泄漏
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  /// 获取详情:按数据来源选择 API
  Future<ModDetail> _load() {
    return SourceManager.getModDetail(widget.source, widget);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 打开链接:站内模组页(mcmod 的 class/{id}.html 或 modrinth.com/mod/{slug})
  /// 默认在应用内跳转详情页,其余链接用浏览器打开。
  /// [forceExternal] 为 true 时一律走浏览器
  Future<void> _openUrl(String url, {bool forceExternal = false}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!forceExternal) {
      final mcmod = _mcmodUrl(uri);
      if (mcmod != null) {
        // 跳过指向当前模组自身的链接,避免堆叠重复详情页
        if (widget.source != ModSource.modrinth && mcmod == widget.id) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetailPage(id: mcmod, source: ModSource.mcmod)),
        );
        return;
      }

      final modrinth = _modrinthUrl(uri);
      if (modrinth != null) {
        // 跳过指向当前项目自身的链接
        if (widget.source == ModSource.modrinth && modrinth == widget.id) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(id: modrinth, source: ModSource.modrinth),
          ),
        );
        return;
      }
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  /// Modrinth 模组页：modrinth.com/mod/{slug} 或 /project/{id|slug} → slug;
  /// 其它路径（版本页/用户页/docs 子域等）返回 null,走浏览器
  static String? _modrinthUrl(Uri uri) {
    if (uri.host != 'modrinth.com' && uri.host != 'www.modrinth.com') {
      return null;
    }
    final m = RegExp(r'^/(?:mod|project)/([a-zA-Z0-9_-]+)/?$').firstMatch(uri.path.toLowerCase());
    return m?.group(1);
  }

  /// 站内模组详情页链接(www.mcmod.cn/class/{id}.html) → 模组 id;
  /// 其它链接返回 null
  static String? _mcmodUrl(Uri uri) {
    if (uri.host != 'www.mcmod.cn' && uri.host != 'mcmod.cn') {
      return null;
    }
    final m = RegExp(r'^/class/(\d+)\.html$').firstMatch(uri.path);
    // 不匹配返回 null(不能用 !,否则外链在 _openUrl 里会直接抛异常)
    return m?.group(1);
  }

  /// 是否为图片地址(富文本里的图片已包成 <a href=图片地址>)
  static bool _imageUrl(String url) {
    final path = Uri
        .tryParse(url)
        ?.path
        .toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?.*)?$').hasMatch(path) || url.contains('i.mcmod.cn');
  }

  /// 灯箱:全屏暗底放大查看图片,点击任意处或关闭按钮退出,支持缩放
  void _showLightbox(String url) {
    showImageBox(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 刘海屏
      appBar: AppBar(
        // 标题可能还在加载，不使用模组名
        title: Text(widget.initialTitle ?? '模组详情'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          // 页地址只依赖 id，详情未加载完也能打开
          IconButton(
            tooltip: '在浏览器中打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () =>
                _openUrl(
                  SourceManager.getUrl(widget.source, widget.id),
                  forceExternal: true,
                ),
          ),
        ],
      ),
      body: FutureBuilder<ModDetail>(
        future: _future,
        builder: (context, snapshot) {
          // 加载界面
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // 错误界面
          if (snapshot.hasError) {
            return _buildError(snapshot);
          }
          // 详情界面
          return _buildSuccess(snapshot.data!);
        },
      ),
    );
  }

  // 错误界面
  Widget _buildError(AsyncSnapshot<ModDetail> snapshot) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text('加载失败\n${snapshot.error}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  /// 正确的模组界面
  Widget _buildSuccess(ModDetail mod) {
    // 按宽度选择布局:窄屏单列滚动,宽屏左右双列独立滚动
    return LayoutBuilder(
      builder: (context, constraints) =>
      constraints.maxWidth < 480
          ? _buildNarrowPage(mod)
          : _buildWidePage(mod),
    );
  }

  /// 宽屏布局:顶部通栏封面+名称,下方左右两栏(左宽右窄)各自独立滚动
  Widget _buildWidePage(ModDetail mod) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部:封面与标题（通栏）
        Padding(
          padding: const EdgeInsets.all(16),
          child: ModCoverWide(mod: mod),
        ),
        // 下方:左宽右窄两栏
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左栏(宽):模组介绍
              Expanded(
                flex: 2,
                child: ListView(
                  controller: _leftController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
                  children: [
                    if (mod.description != null && mod.description!.isNotEmpty) ...[
                      ..._buildDescription(mod, theme),
                    ],
                  ],
                ),
              ),
              // 右栏(窄):相关链接 + 支持版本
              Expanded(
                flex: 1,
                child: ListView(
                  controller: _rightController,
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                  children: [
                    if (mod.links.isNotEmpty) ...[
                      ..._buildLinks(mod),
                    ],
                    if (mod.mcVersions.isNotEmpty) ...[
                      ..._buildModVersion(mod),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 窄屏布局:单列滚动，内容顺序排列
  Widget _buildNarrowPage(ModDetail mod) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ModCoverNarrow(mod: mod),
        if (mod.links.isNotEmpty) ...[
          ..._buildLinks(mod),
        ],
        if (mod.mcVersions.isNotEmpty) ...[
          ..._buildModVersion(mod),
        ],
        if (mod.description != null && mod.description!.isNotEmpty) ...[
          ..._buildDescription(mod, theme),
        ],
      ],
    );
  }

  /// 区块标题:上间距 + titleLarge 标题 + 下间距,配合 ... 展开使用
  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      // 上下间距写入 Padding 中
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          // 右栏较窄时标题可能超宽，Expanded + 省略号兜底,避免溢出报错
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// 相关链接
  List<Widget> _buildLinks(ModDetail mod) {
    return [
      _buildSectionTitle('相关链接', Icons.insert_link_rounded),
      CollapsibleChips(
        chips: [
          for (final link in mod.links)
            ActionChip(
              avatar: Icon(LinkIcons.getLinkIcon(link.name), size: 18),
              label: Text(link.name),
              onPressed: () => _openUrl(link.url),
            ),
        ],
      ),
      const Divider(),
    ];
  }

  /// 支持版本
  List<Widget> _buildModVersion(ModDetail mod) {
    return [
      _buildSectionTitle('支持版本', Icons.check_circle_rounded),
      CollapsibleChips(
        chips: [for (final v in mod.mcVersions) Chip(label: Text(v))],
      ),
      const Divider(),
    ];
  }

  /// 详细内容
  List<Widget> _buildDescription(ModDetail mod, ThemeData theme) {
    return [
      _buildSectionTitle('模组介绍', Icons.article_rounded),
      _buildHTML(mod, theme),
    ];
  }

  /// 正文链接点击:图片地址(清洗时已包成 <a href=图片地址>)走灯箱,
  /// 其余按站内跳转/浏览器规则分流
  void _handleContentLink(String url) {
    if (_imageUrl(url)) {
      _showLightbox(url);
    } else {
      _openUrl(url);
    }
  }

  /// 渲染 HTML 正文(两种来源的描述都是清洗后的 HTML)。
  ///
  /// 按设置里的渲染方法二选一:
  /// - default:自写 HtmlContent(逐标签映射控件,正文零 MouseRegion)
  /// - hyperViewer:hyper_render(单 RenderObject 布局引擎,性能更优)
  Widget _buildHTML(ModDetail mod, ThemeData theme) {
    if (SettingsService.instance.renderType == 'default') {
      return HtmlContent(
        html: mod.description!,
        textStyle: theme.textTheme.bodyMedium,
        onLinkTap: _handleContentLink,
      );
    }
    return _mouseDraggable(
      HyperViewer(
        html: mod.description!,
        mode: HyperRenderMode.sync,
        shrinkWrap: true,
        selectable: false,
        customCss: _hyperCss(theme),
        onLinkTap: _handleContentLink,
      ),
    );
  }

  /// 桌面端 ScrollBehavior 默认只认触摸/手写笔拖拽,鼠标拖不动
  /// 正文里表格的横向滚动容器;包一层开启鼠标/触控板拖拽的配置
  /// (只作用于描述内容,不影响外层列表的既有滚动方式)
  Widget _mouseDraggable(Widget child) {
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
      child: child,
    );
  }

  /// hyper_render 的主题适配:包默认正文样式是 16px 深灰字,用 customCss
  /// 注入正文颜色/字号/字体(字体缩放走 MediaQuery,包默认读取)。
  /// 颜色取 bodyMedium 的常规字体颜色(与普通 Text 控件一致),
  /// 不使用 colorScheme 主题色。
  /// 注意:UDT 树根节点 tagName 是 'document'(HTML/Markdown 均是),
  /// 用 'body' 选择器匹配不到任何节点;注入根节点后靠继承传播到正文,
  /// 行内 style 优先级更高,正文里的颜色文字不受影响
  String _hyperCss(ThemeData theme) {
    final textStyle = theme.textTheme.bodyMedium;
    final color = (textStyle?.color ?? theme.colorScheme.onSurface).toARGB32();
    final hex = color.toRadixString(16).padLeft(8, '0').substring(2);
    final family = textStyle?.fontFamily;
    // 包内 CSS 解析器把 font-family 整值去引号后当作单个家族名,
    // 不支持逗号分隔的回退列表;取 bodyMedium 的家族名(应用字体)
    final familyCss =
    (family == null || family.isEmpty) ? '' : 'font-family: $family; ';
    return 'document { color: #$hex; '
        'font-size: ${textStyle?.fontSize ?? 14}px; '
        '$familyCss}';
  }
}