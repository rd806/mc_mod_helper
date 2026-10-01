import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/mcmod.dart';
import '../../model/author/author_detail.dart';
import '../../model/project/project_summary.dart';
import '../../setting/display_settings.dart';
import '../../setting/value/display.dart';
import '../../setting/value/source.dart';
import '../../widget/common/error_view.dart';
import '../../widget/common/section_title.dart';
import '../../widget/detail/author_cover.dart';
import '../../widget/detail/scroll_button.dart';
import '../../widget/dialog/captcha_dialog.dart';

/// 作者页:从详情页「开发团队」卡片的作者芯片进来。
///
/// 骨架照详情页(AppBar + 首屏 FutureBuilder 式的加载/错误/重试 + 宽窄留白),
/// 列表照浏览页(滚动到底增量加载 + 尾部三态);页内只有一份内容,
/// 所以不设页签、不分左右栏。
class AuthorPage extends StatefulWidget {
  const AuthorPage({
    super.key,
    required this.id,
    required this.source,
    this.initialName,
    this.initialAvatarUrl,
    this.initialUrl,
  });

  /// 站点用户 id:mcmod 是作者页地址里的数字,Modrinth 是 user.id,
  /// CurseForge 是 authors[].id
  final String id;

  /// 数据来源:'mcmod' / 'modrinth' / 'curseforge',决定用哪个 API 加载
  final ModSource source;

  /// 头部加载完成前显示的名字(来自详情页的作者卡片)
  final String? initialName;

  /// 同上,头像
  final String? initialAvatarUrl;

  /// 站点给的主页地址。CurseForge 的作者主页按用户名拼,数字 id 拼不出来,
  /// 只有详情页的作者卡片知道这个地址
  final String? initialUrl;

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  final ScrollController _controller = ScrollController();

  /// 作者头部(加载完成前为 null,界面先用卡片带来的名字/头像)
  AuthorDetail? _author;

  /// 作品列表状态
  final List<ProjectSummary> _projects = [];
  int _seq = 0;
  int _page = 0;
  int? _totalPages;
  bool _initialLoading = true;
  String? _error;
  bool _loading = false;
  bool _loadMoreFailed = false;

  bool get _hasMore => _totalPages == null || _page < _totalPages!;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // 距底部 600px 内触发预加载下一页
      if (_controller.position.pixels >=
          _controller.position.maxScrollExtent - 600) {
        _loadNextPage();
      }
    });
    _loadFirstPage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 拉取第 1 页(首次进入 / 刷新)
  Future<void> _loadFirstPage() async {
    final seq = ++_seq;
    if (!mounted) return;
    setState(() {
      _initialLoading = true;
      _error = null;
      // 本次会作废在飞的翻页请求,它不会再把 _loading 收回,这里自己清掉
      _loading = false;
      _loadMoreFailed = false;
    });
    if (_controller.hasClients) _controller.jumpTo(0);
    try {
      final result = await SourceManager.getAuthor(widget.source, widget.id);
      if (!mounted || seq != _seq) return;
      setState(() {
        _author = result.author;
        _projects
          ..clear()
          ..addAll(result.author.projects ?? const []);
        _page = 1;
        _totalPages = result.totalPages;
        _initialLoading = false;
      });
      _fillViewportIfNeeded();
    } on McmodCaptchaException catch (e) {
      if (!mounted || seq != _seq) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted || seq != _seq) return;
      if (!ok) {
        setState(() {
          _error = e.toString();
          _initialLoading = false;
        });
        return;
      }
      await _loadFirstPage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  /// 首屏不满一屏时滚动监听永远不会触发,主动补拉下一页
  void _fillViewportIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _controller.hasClients &&
          _controller.position.maxScrollExtent == 0 &&
          _hasMore) {
        _loadNextPage();
      }
    });
  }

  /// 加载下一页
  Future<void> _loadNextPage() async {
    // 守卫必须在自增序号之前:滚动监听每帧都会调用这里,若先自增再返回,
    // 那些什么都没做的空调用也会把序号推走,在飞的那次请求落地时被判为过期,
    // 响应被丢弃且 _loading 永远收不回 false —— 尾部就卡在「加载中」
    if (_loading || _loadMoreFailed || !_hasMore || _initialLoading) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final result = await SourceManager.getAuthor(
        widget.source,
        widget.id,
        page: _page + 1,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _projects.addAll(result.author.projects ?? const []);
        _page++;
        _totalPages = result.totalPages;
        _loading = false;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted || seq != _seq) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted || seq != _seq) return;
      if (!ok) {
        // 翻页时放弃验证:已加载的内容留在原地,尾部给重试
        setState(() {
          _loading = false;
          _loadMoreFailed = true;
        });
        return;
      }
      await _loadFirstPage();
    } catch (_) {
      // 保留已加载内容,尾部显示重试
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadMoreFailed = true;
      });
    }
  }

  /// 在浏览器中打开作者主页
  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(
      widget.initialUrl ?? SourceManager.getAuthorUrl(widget.source, widget.id),
    );
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 标题可能还在加载,用卡片带来的名字兜底
        title: Text(_author?.name ?? widget.initialName ?? '作者'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loadFirstPage,
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _loadFirstPage);
    }
    final author = _author;
    if (author == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 宽屏左右留白(与详情页同样的 800 断点)
        final wide = constraints.maxWidth >= 800;
        final side = wide ? 64.0 : 16.0;
        return Stack(
          children: [
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: _loadFirstPage,
                child: ListenableBuilder(
                  // 监听展示方式:改成卡片/列表后无需重进页面即时切换
                  listenable: DisplaySettings.instance,
                  builder: (context, _) => CustomScrollView(
                    controller: _controller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: AuthorCover(
                            author: author,
                            fallbackName: widget.initialName,
                            fallbackAvatarUrl: widget.initialAvatarUrl,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: SectionTitle(
                            title: '作品 (${_projects.length})',
                            icon: Icons.folder_rounded,
                          ),
                        ),
                      ),
                      if (_projects.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: Text('这里还没有他的作品')),
                          ),
                        )
                      else ...[
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(side, 0, side, 8),
                          sliver: DisplayManager.buildSliver(
                            DisplaySettings.instance.displayStyle,
                            _projects,
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildFooter()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // 返回顶部(ScrollToTopButton 返回的是 Positioned,必须放在 Stack 里)
            ScrollToTopButton(
              controller: _controller,
              padding: const EdgeInsets.only(bottom: 20, right: 20),
            ),
          ],
        );
      },
    );
  }

  /// 列表尾部:加载中 / 加载失败重试 / 已经到底
  Widget _buildFooter() {
    final Widget child;
    if (_loading) {
      child = const CircularProgressIndicator();
    } else if (_loadMoreFailed) {
      child = TextButton(
        onPressed: () {
          setState(() => _loadMoreFailed = false);
          _loadNextPage();
        },
        child: const Text('加载失败,点击重试'),
      );
    } else if (!_hasMore) {
      child = Text(
        '已经到底啦',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: child),
    );
  }
}
