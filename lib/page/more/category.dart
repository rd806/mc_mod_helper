import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/api/source.dart';

import '../../model/mod_category.dart';
import '../../api/mcmod.dart';
import '../../api/modrinth.dart';
import '../../model/mod_summary.dart';
import '../../widget/common/error_view.dart';
import '../../widget/mod/mod_card.dart';

/// 分类模组列表页：网格卡片展示，滚动到底自动加载下一页
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.category});

  final ModCategory category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final ScrollController _controller = ScrollController();

  final List<ModSummary> _mods = [];

  /// 已成功加载的页数(0 = 尚未加载)
  int _page = 0;

  /// 总页数;未知时视为还有更多
  int? _totalPages;
  bool _initialLoading = true;
  String? _error;

  /// 任一请求进行中(防重复触发)
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
    _loadInitial();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按分类的数据来源拉取第 [page] 页
  Future<({List<ModSummary> mods, int totalPages})> _fetchPage(int page) {
    switch (widget.category.source) {
      case ModSource.mcmod:
        return McmodApi.getCategoryMods(widget.category.id, page: page);
      case ModSource.modrinth:
        return ModrinthApi.getCategoryMods(widget.category.id, page: page);
      case ModSource.curseforge:
        return CurseforgeApi.getCategoryMods(widget.category.id, page: page);
    }
  }

  /// 加载首页内容
  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final result = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        _mods
          ..clear()
          ..addAll(result.mods);
        _page = 1;
        _totalPages = result.totalPages;
        _initialLoading = false;
      });
      // 首屏不满一屏时滚动监听永远不会触发,需要主动补拉
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _controller.hasClients &&
            _controller.position.maxScrollExtent == 0 &&
            _hasMore) {
          _loadNextPage();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  /// 加载下一页内容
  Future<void> _loadNextPage() async {
    // 错误加载
    if (_loading || _loadMoreFailed || !_hasMore || _initialLoading) return;
    setState(() => _loading = true);
    try {
      final result = await _fetchPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _mods.addAll(result.mods);
        _page++;
        _totalPages = result.totalPages;
        _loading = false;
      });
    } catch (_) {
      // 保留已加载内容,尾部显示重试
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadMoreFailed = true;
      });
    }
  }

  /// 重新加载本页:重新拉取第 1 页(非静默,显示加载动画)
  Future<void> _refresh() async {
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // 主体
  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _loadInitial);
    }
    if (_mods.isEmpty) {
      return const Center(child: Text('该分类暂无模组'));
    }
    // 模组列表
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 480;
        return CustomScrollView(
          controller: _controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: narrow ? _buildModList() : _buildModGrid(constraints),
            ),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        );
      },
    );
  }

  // 窄屏列表
  // 模组单行排列（左侧封面，右侧标题与统计）
  Widget _buildModList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => ModCardRow(mod: _mods[i]),
        childCount: _mods.length,
      ),
    );
  }

  // 宽屏Grid
  Widget _buildModGrid(BoxConstraints constraints) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (constraints.maxWidth / 225).floor(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => ModCardColumn(mod: _mods[i]),
        childCount: _mods.length,
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
