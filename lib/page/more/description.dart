import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/widget/detail/intro/selection_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/mcmod.dart';
import '../../api/modrinth.dart';
import '../../model/mod/mod_detail.dart';
import '../../model/mod/mod_summary.dart';
import '../../service/agent/agent.dart';
import '../../widget/agent/agent_sheet.dart';
import '../../widget/handler/captcha_dialog.dart';
import '../../widget/common/image_box.dart';
import '../../widget/handler/scroll_button.dart';
import '../../widget/detail/card/authors_card.dart';
import '../../widget/detail/intro/cover.dart';
import '../../widget/detail/card/description_card.dart';
import '../../widget/detail/card/environment_card.dart';
import '../../widget/detail/card/links_card.dart';
import '../../widget/mod/favorite_toggle.dart';

/// 模组详情页
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.id,
    required this.source,
    this.initialTitle,
    this.initialDescription,
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
  // 当前展示的组件
  int _currentIndex = 0;
  // 待加载的信息
  late Future<ModDetail> _future;

  final List<(String, int)> _button = [('介绍', 0), ('信息', 1)];
  // 左右控制器
  final ScrollController _leftController = ScrollController();
  final ScrollController _rightController = ScrollController();
  // 窄屏整页滚动控制器(返回顶部按钮需要驱动它)
  final ScrollController _narrowController = ScrollController();

  void _switchTo(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

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
    _narrowController.dispose();
    super.dispose();
  }

  /// 获取详情:按数据来源选择 API;
  /// 被站点安全验证拦截时弹窗人工输入验证码,通过后自动重试
  Future<ModDetail> _load() async {
    try {
      switch (widget.source) {
        case ModSource.mcmod:
          return await McmodApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
          );
        case ModSource.modrinth:
          return await ModrinthApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
          );
        case ModSource.curseforge:
          return await CurseforgeApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
          );
      }
    } on McmodCaptchaException catch (e) {
      if (!mounted) rethrow;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!ok) rethrow; // 用户取消:走错误界面(显示验证提示 + 重试按钮)
      return _load();
    }
  }

  /// 重新加载
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 打开链接:站内模组页(mcmod 的 class/{id}.html 或 modrinth.com/mod/{slug})
  /// 默认在应用内跳转详情页,其余链接用浏览器打开。
  /// [forceExternal] 为 true 时一律走浏览器
  Future<void> _openUrl(String url, {bool forceExternal = false}) async {
    // 打开图片灯箱
    if (_imageUrl(url)) {
      showImageBox(context, url);
      return;
    }
    // 其他链接
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!forceExternal) {
      final mcmod = _mcmodUrl(uri);
      if (mcmod != null) {
        // 跳过指向当前模组自身的链接,避免堆叠重复详情页
        if (widget.source != ModSource.modrinth && mcmod == widget.id) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(id: mcmod, source: ModSource.mcmod),
          ),
        );
        return;
      }

      final modrinth = _modrinthUrl(uri);
      if (modrinth != null) {
        // 跳过指向当前项目自身的链接
        if (widget.source == ModSource.modrinth && modrinth == widget.id) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DetailPage(id: modrinth, source: ModSource.modrinth),
          ),
        );
        return;
      }
    }
    // 打开链接
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
  static String? _mcmodUrl(Uri uri) {
    if (uri.host != 'www.mcmod.cn' && uri.host != 'mcmod.cn') {
      return null;
    }
    final m = RegExp(r'^/class/(\d+)\.html$').firstMatch(uri.path);
    // 不匹配返回 null(不能用 !,否则外链在 _openUrl 里会直接抛异常)
    return m?.group(1);
  }

  /// 是否为图片地址（富文本里的图片已包成 <a href=图片地址>）
  static bool _imageUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?.*)?$').hasMatch(path) ||
        url.contains('i.mcmod.cn');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 刘海屏
      appBar: AppBar(
        // 标题可能还在加载，不使用模组名
        title: Text(widget.initialTitle ?? '模组详情'),
        actions: [
          // 收藏:详情未加载完时用初始信息构造摘要
          // (id+来源已足够匹配收藏,加载完再补全标题/图标)
          FutureBuilder<ModDetail>(
            future: _future,
            builder: (context, snapshot) {
              final mod = snapshot.hasData
                  ? ModSummary.fromDetail(snapshot.data!)
                  : ModSummary(
                      id: widget.id,
                      title: widget.initialTitle ?? widget.id,
                      description: widget.initialDescription ?? '',
                      source: widget.source,
                    );
              return FavoriteToggle(mod: mod);
            },
          ),
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
      // 模组助手:总结当前模组 / 推荐相似模组。
      // 详情还没加载出来时没有可总结的内容,先不显示入口
      floatingActionButton: FutureBuilder<ModDetail>(
        future: _future,
        builder: (context, snapshot) {
          final mod = snapshot.data;
          if (mod == null) return const SizedBox.shrink();
          return FloatingActionButton(
            tooltip: '模组助手',
            onPressed: () =>
                showAgentSheet(context, mod: AgentModContext.fromDetail(mod)),
            child: const Icon(Icons.smart_toy_outlined),
          );
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

  /// 正确的模组界面:按宽度选布局,并把返回顶部按钮浮在内容之上
  Widget _buildSuccess(ModDetail mod) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 800;
        return Stack(
          children: [
            Positioned.fill(
              child: narrow ? _buildNarrowPage(mod) : _buildWidePage(mod),
            ),
            // 返回顶部:窄屏滚整页(含封面),宽屏滚左栏正文列。
            // 右下角让给助手悬浮按钮,故整体上移
            ScrollToTopButton(
              controller: narrow ? _narrowController : _leftController,
              padding: const EdgeInsets.only(bottom: 96, right: 20),
            ),
          ],
        );
      },
    );
  }

  /// 宽屏布局:顶部通栏封面+名称,下方左右两栏(左宽右窄)各自独立滚动
  Widget _buildWidePage(ModDetail mod) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部:封面与标题（通栏）
        Padding(
          padding: const EdgeInsets.fromLTRB(64, 16, 64, 16),
          child: ModCoverWide(mod: mod),
        ),
        // 下方:左宽右窄两栏
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左栏(宽):模组介绍
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(64, 0, 0, 0),
                  child: ListView(
                    controller: _leftController,
                    padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                    children: [_buildDescription(mod)],
                  ),
                ),
              ),
              // 右栏(窄):相关链接 + 支持版本
              SizedBox(
                width: min(450, MediaQuery.of(context).size.width * 0.4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 54, 0),
                  child: ListView(
                    controller: _rightController,
                    padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                    children: [_buildOther(mod)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 窄屏布局:单列滚动,封面滚出、SelectionButton 吸顶,下方正文。
  ///
  /// 正文按当前页签替换对应 sliver,而不是用 IndexedStack 叠放两个子项:
  /// IndexedStack 高度取所有子项的最大者——长「介绍」会让切到短「信息」
  /// 后仍保留巨大的滚动范围(下方大段空白)。只放当前页签,滚动范围
  /// 与当前内容一致。
  Widget _buildNarrowPage(ModDetail mod) {
    return CustomScrollView(
      controller: _narrowController,
      slivers: [
        // 封面区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: ModCoverNarrow(mod: mod),
          ),
        ),
        // SelectionButton 吸顶效果
        SliverPersistentHeader(
          pinned: true, // 关键：固定吸顶
          delegate: _SelectionButtonSliverDelegate(
            button: _button,
            selectedIndex: _currentIndex,
            switchTo: _switchTo,
            // 吸顶条高度与按钮实际高一致(按当前字号计算),不留空带不裁剪
            barHeight: SelectionButton.preferredHeight(context),
          ),
        ),
        // 正文:只放当前页签,滚动范围与内容一致
        if (_currentIndex == 0) _introSliver(mod) else _infoSliver(mod),
      ],
    );
  }

  /// 「介绍」正文:整段描述(可能很长,作为单个块随页面滚动)
  Widget _introSliver(ModDetail mod) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsetsGeometry.fromLTRB(16, 0, 16, 16),
        child: DescriptionCard(mod: mod, onLinkTap: _openUrl),
      ),
    );
  }

  /// 「信息」正文:环境/作者/链接/版本区块
  Widget _infoSliver(ModDetail mod) {
    return SliverPadding(
      padding: const EdgeInsetsGeometry.fromLTRB(16, 0, 16, 16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          EnvironmentCard(mod: mod),
          AuthorsCard(mod: mod),
          LinksCard(mod: mod, onOpenUrl: _openUrl),
        ]),
      ),
    );
  }

  /// 描述区域
  Widget _buildDescription(ModDetail mod) {
    return DescriptionCard(mod: mod, onLinkTap: _openUrl);
  }

  /// 其他页签: 环境/作者/链接/版本四个区块
  Widget _buildOther(ModDetail mod) {
    return Column(
      children: [
        EnvironmentCard(mod: mod),
        AuthorsCard(mod: mod),
        LinksCard(mod: mod, onOpenUrl: _openUrl),
      ],
    );
  }
}

/// SelectionButton 的 SliverPersistentHeader 代理
/// 实现吸顶效果
class _SelectionButtonSliverDelegate extends SliverPersistentHeaderDelegate {
  _SelectionButtonSliverDelegate({
    required this.button,
    required this.selectedIndex,
    required this.switchTo,
    required this.barHeight,
  });

  final List<(String, int)> button;
  final int selectedIndex;
  final void Function(int) switchTo;

  /// 吸顶条的高度
  final double barHeight;

  // 高度固定、不随滚动收缩,min/max 相等
  @override
  double get minExtent => barHeight;

  @override
  double get maxExtent => barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 这里的 Container 背景色防止滚动内容从吸顶条下方透出
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SelectionButton(
        button: button,
        selectedIndex: selectedIndex,
        switchTo: switchTo,
      ),
    );
  }

  @override
  bool shouldRebuild(_SelectionButtonSliverDelegate oldDelegate) {
    return selectedIndex != oldDelegate.selectedIndex ||
        button != oldDelegate.button ||
        barHeight != oldDelegate.barHeight;
  }
}
