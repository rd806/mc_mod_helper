import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/setting/value/display.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/widget/filter/search_bar.dart';
import 'package:mc_mod_helper/widget/filter/filter_bar.dart';

import '../api/mcmod.dart';
import '../icon/icon_manager.dart';
import '../model/filter/sort_method.dart';
import '../model/project/project_category.dart';
import '../model/project/project_summary.dart';
import '../model/project/project_type.dart';
import '../model/project/project_version.dart';
import '../widget/dialog/captcha_dialog.dart';
import '../widget/common/error_view.dart';
import '../widget/dialog/switch_dialog.dart';

/// 浏览页:首页与探索页合并而来。
///
/// 顶部的类型标签决定浏览哪一类资源(模组 / 整合包),下方的筛选栏
/// ([FilterBar])决定这一类里的分类 / 版本 / 排序组合,没有「查看更多」,
/// 所有内容都在本页滚动到底自动加载下一页。
///
/// 类型与数据来源都算「作用域」(决定分类与版本的候选集),
/// 变化时要清掉已选的分类/版本;筛选栏那三项才是「筛选条件」。
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, this.initialFilter});

  /// 预设筛选(详情页的版本胶囊跳进来时带上该版本与类型)。
  /// 为空则用「模组 + 当前数据来源 + 默认排序 + 不带分类版本」
  final Filter? initialFilter;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final ScrollController _controller = ScrollController();

  /// 当前筛选:分类 / 版本 / 排序的唯一事实来源
  late Filter _filter;

  /// 筛选栏的可选项(按数据来源抓取)
  List<ProjectCategory> _categories = const [];
  List<ProjectVersion> _versions = const [];
  bool _optionsLoading = true;
  String? _optionsError;

  /// 列表状态
  final List<ProjectSummary> _mods = [];
  int _seq = 0;
  int _page = 0;
  int? _totalPages;
  bool _initialLoading = true;
  String? _error;
  bool _loading = false;
  bool _loadMoreFailed = false;

  /// 筛选变更的防抖计时器:连点几个 chip 只发一次请求
  Timer? _applyDebounce;

  /// 上次见到的设置值,用于判断哪些变化需要重拉
  ModSource? _lastDataSource;
  DisplayStyle? _lastDisplayStyle;

  bool get _hasMore => _totalPages == null || _page < _totalPages!;

  /// 抓选项时的两次 await 之间,作用域有没有被改掉(换来源 / 换类型);
  /// 改了就当这次结果过期,别把上一个作用域的分类/版本盖上去
  bool _scopeIsCurrent(ModSource source, ProjectType type) =>
      source == DisplaySettings.instance.dataSource && type == _filter.type;

  @override
  void initState() {
    super.initState();
    _filter =
        widget.initialFilter ??
        Filter(
          type: ProjectTypeManager.supportedTypes.first,
          modSource: DisplaySettings.instance.dataSource,
          sortMethod: SortMethod.none,
        );
    _lastDataSource = _filter.modSource;
    _controller.addListener(() {
      // 距底部 600px 内触发预加载下一页
      if (_controller.position.pixels >=
          _controller.position.maxScrollExtent - 600) {
        _loadNextPage();
      }
    });
    DisplaySettings.instance.addListener(_onSettingsChanged);
    _loadOptions();
    _loadFirstPage();
  }

  @override
  void dispose() {
    _applyDebounce?.cancel();
    DisplaySettings.instance.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 设置变化:换来源要清掉分类/版本(不同站点的分类 id 与版本号体系不同,
  /// 留着只会查到空结果或语义不相干的结果),排序是三者共用的词汇则保留;
  /// 换展示方式只重建布局
  void _onSettingsChanged() {
    if (DisplaySettings.instance.displayStyle != _lastDisplayStyle) {
      setState(() => _lastDisplayStyle = DisplaySettings.instance.displayStyle);
    }
    final source = DisplaySettings.instance.dataSource;
    if (source == _lastDataSource) return;
    _lastDataSource = source;
    _resetScope(
      Filter(
        type: _filter.type,
        modSource: source,
        sortMethod: _filter.sortMethod,
      ),
    );
  }

  /// 切换项目类型(顶部的类型标签)。
  ///
  /// 类型与来源一样是「作用域」:各类型的分类 id 与版本集合都不同
  /// (mcmod 的 category=1 在模组下是「科技」、在整合包下是「科技整合包」),
  /// 所以换类型同样要清掉已选的分类与版本,排序保留
  void _onTypeChanged(ProjectType type) {
    if (type == _filter.type) return;
    _resetScope(
      Filter(
        type: type,
        modSource: DisplaySettings.instance.dataSource,
        sortMethod: _filter.sortMethod,
      ),
    );
  }

  /// 作用域变化(换类型 / 换来源):清掉分类与版本,选项与第 1 页都重拉
  void _resetScope(Filter next) {
    setState(() {
      _filter = next;
      _categories = const [];
      _versions = const [];
      _optionsLoading = true;
      _optionsError = null;
    });
    _loadOptions();
    _loadFirstPage();
  }

  /// 抓取筛选栏的可选项(分类 + 版本,按当前来源与类型)
  Future<void> _loadOptions() async {
    final source = DisplaySettings.instance.dataSource;
    final type = _filter.type;
    try {
      // 两个请求共用来源自己的节流,并发发出会互相插队,故顺序等待
      final categories = await SourceManager.getCategory(source, type);
      if (!mounted || !_scopeIsCurrent(source, type)) return;
      setState(() => _categories = categories);
      final versions = await SourceManager.getVersions(source, type);
      if (!mounted || !_scopeIsCurrent(source, type)) return;
      setState(() {
        _versions = versions;
        _optionsLoading = false;
        _optionsError = null;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _optionsError = e.toString();
          _optionsLoading = false;
        });
        return;
      }
      await _loadOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optionsError = e.toString();
        _optionsLoading = false;
      });
    }
  }

  /// 筛选栏改动:先只更新选中态与摘要,停手后才真正请求。
  ///
  /// 每次请求都受站点 1s 节流约束,不防抖的话连点两个 chip 会排出两次请求,
  /// 用户看到的进度比手速慢好几拍
  void _onFilterChanged(
    ProjectCategory? category,
    ProjectVersion? version,
    SortMethod sort,
  ) {
    final next = Filter(
      type: _filter.type,
      modSource: DisplaySettings.instance.dataSource,
      sortMethod: sort,
      category: category,
      version: version,
    );
    if (next == _filter) return; // 点的就是当前项,不重拉
    setState(() => _filter = next);
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 350), _loadFirstPage);
  }

  /// 拉取第 1 页(首次进入 / 筛选变更 / 刷新)
  Future<void> _loadFirstPage() async {
    final seq = ++_seq;
    _applyDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      _initialLoading = true;
      _error = null;
      // 本次会作废在飞的翻页请求(序号已变),它不会再把 _loading 收回,
      // 这里必须自己清掉,否则换筛选后尾部永远停在「加载中」
      _loading = false;
      _loadMoreFailed = false;
    });
    // 筛选变了就是换了一整份内容,必须回顶部:否则用户停在「旧结果的第 4 屏」,
    // 新结果会从中段开始显示,看着像丢了内容
    if (_controller.hasClients) _controller.jumpTo(0);
    try {
      final result = await SourceManager.getFilteredMods(_filter, page: 1);
      if (!mounted || seq != _seq) return;
      setState(() {
        _mods
          ..clear()
          ..addAll(result.mods);
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
      final result = await SourceManager.getFilteredMods(
        _filter,
        page: _page + 1,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _mods.addAll(result.mods);
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
        // (别整个换成错误页,那会把用户眼前的列表清空)
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

  Future<void> _refresh() async {
    await Future.wait([_loadOptions(), _loadFirstPage()]);
  }

  @override
  Widget build(BuildContext context) {
    // 类型标签:数量与下标都由 [ProjectTypeManager.supportedTypes] 决定,
    // 初始下标跟着当前筛选的类型走(详情页的版本胶囊可能预设成整合包)
    final types = ProjectTypeManager.supportedTypes;
    final typeIndex = types.indexOf(_filter.type);

    return DefaultTabController(
      length: types.length,
      initialIndex: typeIndex < 0 ? 0 : typeIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ActionChip(
                avatar: IconManager.getIconForDataSource(
                  DisplaySettings.instance.dataSource,
                ),
                label: Text(
                  SourceManager.getSourceString(
                    DisplaySettings.instance.dataSource,
                  ),
                ),
                onPressed: () => showSwitchSourceDialog(context),
              ),
              const SizedBox(width: 10),
              Expanded(child: FakeSearchBar()),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
          ],
          bottom: TabBar(
            onTap: (index) => _onTypeChanged(types[index]),
            tabs: [
              for (final type in types)
                Tab(text: ProjectTypeManager.getTypeTitle(type)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsetsGeometry.all(16),
              child: FilterBar(
                filter: _filter,
                categories: _categories,
                versions: _versions,
                optionsLoading: _optionsLoading,
                optionsError: _optionsError,
                onRetryOptions: () {
                  setState(() {
                    _optionsLoading = true;
                    _optionsError = null;
                  });
                  _loadOptions();
                },
                onChanged: _onFilterChanged,
              ),
            ),
            Expanded(
              child: RefreshIndicator(onRefresh: _refresh, child: _buildBody()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _loadFirstPage);
    }
    if (_mods.isEmpty) {
      // 空态也要能下拉刷新,所以套一层可滚动容器
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('没有符合条件的模组')),
          ),
        ],
      );
    }
    // 模组列表(按设置的展示方式:卡片/列表/自适应);
    // 监听设置,修改展示方式后无需重进页面即时切换
    return ListenableBuilder(
      listenable: DisplaySettings.instance,
      builder: (context, _) => CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: DisplayManager.buildSliver(
              DisplaySettings.instance.displayStyle,
              _mods,
            ),
          ),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
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
