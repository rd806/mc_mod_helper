import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:mc_mod_helper/widget/description/cover.dart';
import 'package:mc_mod_helper/widget/link_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/mcmod.dart';
import '../api/modrinth.dart';
import '../model/mod_detail.dart';
import '../widget/description/collapsible_chips.dart';
import '../widget/description/image_box.dart';

/// 模组详情页
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.id,
    this.initialTitle,
    this.initialDescription,
    this.source = 'mcmod',
  });

  /// 统一模组标识(字符串):MC百科为数字字符串(如 '123'),Modrinth 为 slug(如 'jei')
  final String id;

  /// 数据来源:'mcmod' 或 'modrinth',决定用哪个 API 加载详情
  final String source;

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
    return widget.source == 'modrinth'
        ? ModrinthApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
          )
        : McmodApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
          );
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
      final modId = _mcmodUrl(uri);
      if (modId != null) {
        // 跳过指向当前模组自身的链接,避免堆叠重复详情页
        if (widget.source != 'modrinth' && '$modId' == widget.id) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetailPage(id: '$modId')),
        );
        return;
      }
      final slug = _modrinthUrl(uri);
      if (slug != null) {
        // 跳过指向当前项目自身的链接
        if (widget.source == 'modrinth' && slug == widget.id) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(id: slug, source: 'modrinth'),
          ),
        );
        return;
      }
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  /// Modrinth 模组页：modrinth.com/mod/{slug} 或 /project/{id|slug} → slug;
  /// 其它路径（版本页/用户页/docs 子域等）返回 null,走浏览器
  static String? _modrinthUrl(Uri uri) {
    if (uri.host != 'modrinth.com' && uri.host != 'www.modrinth.com') {
      return null;
    }
    final m = RegExp(r'^/(?:mod|project)/([a-zA-Z0-9_-]+)/?$')
        .firstMatch(uri.path.toLowerCase());
    return m?.group(1);
  }

  /// 站内模组详情页链接(www.mcmod.cn/class/{id}.html) → 模组 id;
  /// 其它链接返回 null
  static int? _mcmodUrl(Uri uri) {
    if (uri.host != 'www.mcmod.cn' && uri.host != 'mcmod.cn') return null;
    final m = RegExp(r'^/class/(\d+)\.html$').firstMatch(uri.path);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// 是否为图片地址(富文本里的图片已包成 <a href=图片地址>)
  static bool _imageUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?.*)?$').hasMatch(path) ||
        url.contains('i.mcmod.cn');
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
            onPressed: () => _openUrl(
              widget.source == 'modrinth'
                  ? 'https://modrinth.com/mod/${widget.id}'
                  : 'https://www.mcmod.cn/class/${widget.id}.html',
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
      builder: (context, constraints) => constraints.maxWidth < 480
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
                    if (mod.description != null &&
                        mod.description!.isNotEmpty) ...[
                      _buildSectionTitle('模组介绍', Icons.article_rounded),
                      _buildDescription(mod, theme),
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
                      _buildSectionTitle('相关链接', Icons.insert_link_rounded),
                      _buildLinks(mod),
                      const Divider(),
                    ],
                    if (mod.mcVersions.isNotEmpty) ...[
                      _buildSectionTitle('支持版本', Icons.check_circle_rounded),
                      _buildModVersion(mod),
                      const Divider(),
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
          _buildSectionTitle('相关链接', Icons.insert_link_rounded),
          _buildLinks(mod),
          const Divider(),
        ],
        if (mod.mcVersions.isNotEmpty) ...[
          _buildSectionTitle('支持版本', Icons.check_circle_rounded),
          _buildModVersion(mod),
          const Divider(),
        ],
        if (mod.description != null && mod.description!.isNotEmpty) ...[
          _buildSectionTitle('模组介绍', Icons.article_rounded),
          _buildDescription(mod, theme),
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

  // 相关链接
  Widget _buildLinks(ModDetail mod) {
    return CollapsibleChips(
      chips: [
        for (final link in mod.links)
          ActionChip(
            avatar: Icon(LinkIcons.getLinkIcon(link.name), size: 18),
            label: Text(link.name),
            onPressed: () => _openUrl(link.url),
          ),
      ],
    );
  }

  // 支持版本
  Widget _buildModVersion(ModDetail mod) {
    return CollapsibleChips(
      chips: [for (final v in mod.mcVersions) Chip(label: Text(v))],
    );
  }

  // 详细内容
  Widget _buildDescription(ModDetail mod, ThemeData theme) {
    // 富文本渲染:标题、加粗、颜色、图片、表格、列表等。
    // 图片已包成 <a href=图片地址>，点击时走灯箱放大
    //
    // 用 SelectionContainer.disabled 包裹:fwfh 检测不到选择容器后,
    // 不会给每个文本块包 MouseRegion(cursor: text),大幅减少正文里的
    // MouseRegion 数量,避免悬停处内容在帧内重建时触发 Flutter 框架
    // MouseTracker 的 '_debugDuringDeviceUpdate' 断言(debug 模式报错)。
    return SelectionContainer.disabled(
      child: HtmlWidget(
        mod.description!,
        factoryBuilder: () => _HtmlWidgetFactory(),
        textStyle: theme.textTheme.bodyMedium,
        // 超链接处理
        onTapUrl: (url) {
          if (_imageUrl(url)) {
            _showLightbox(url);
          } else {
            _openUrl(url);
          }
          return true;
        },
      ),
    );
  }
}

/// 自定义 fwfh 工厂:链接点击不包 MouseRegion(cursor)。
///
/// fwfh 默认给每个可点击链接包 MouseRegion 以显示点击光标,
/// 正文里的链接(含画廊图片)成百上千,悬停处内容在帧内重建时会
/// 触发 Flutter MouseTracker 的 '_debugDuringDeviceUpdate' 断言;
/// 去掉光标 MouseRegion 后点击功能保留(仅光标样式损失,可接受)。
class _HtmlWidgetFactory extends WidgetFactory {
  @override
  Widget? buildGestureDetector(
    BuildTree tree,
    Widget child,
    GestureRecognizer recognizer,
  ) {
    if (recognizer is TapGestureRecognizer) {
      return GestureDetector(onTap: recognizer.onTap, child: child);
    }
    return child;
  }
}
