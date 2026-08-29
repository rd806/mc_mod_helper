import 'package:flutter/material.dart';

import '../models/mod.dart';
import '../api/mcmod.dart';
import '../widgets/error_view.dart';
import 'detail.dart';

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

    Future<void> _loadInitial() async {
        setState(() {
            _initialLoading = true;
            _error = null;
        });
        try {
            final result = await McmodApi.getCategoryMods(widget.category.id);
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
                if (mounted && _controller.hasClients &&
                    _controller.position.maxScrollExtent == 0 && _hasMore) {
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

    Future<void> _loadNextPage() async {
        if (_loading || _loadMoreFailed || !_hasMore || _initialLoading) return;
        setState(() => _loading = true);
        try {
            final result =
                await McmodApi.getCategoryMods(widget.category.id, page: _page + 1);
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

    @override
    Widget build(BuildContext context) {
        return Scaffold(
        appBar: AppBar(title: Text(widget.category.name)),
        body: _buildBody(),
        );
    }

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
        return LayoutBuilder(
        builder: (context, constraints) {
            final columns = (constraints.maxWidth / 180).floor().clamp(2, 4);
            return CustomScrollView(
            controller: _controller,
            slivers: [
                SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                    (context, i) => _ModCard(mod: _mods[i]),
                    childCount: _mods.length,
                    ),
                ),
                ),
                SliverToBoxAdapter(child: _buildFooter()),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

/// 分类页的模组卡片:封面 + 标题 + 统计
class _ModCard extends StatelessWidget {
    const _ModCard({required this.mod});

    final ModSummary mod;

    @override
    Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(
                builder: (_) => DetailPage(
                    id: mod.id,
                    initialTitle: mod.displayName,
                    initialDescription: mod.description,
                ),
                ),
            );
            },
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Expanded 吸收剩余高度,任何文本长度下都不会溢出
                Expanded(
                child: mod.iconUrl == null
                    ? _buildCoverPlaceholder(theme)
                    : Image.network(
                        mod.iconUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverPlaceholder(theme),
                    ),
                ),
                Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                        mod.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                    ),
                    if (mod.statsText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                        mod.statsText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                        ),
                        ),
                    ],
                    ],
                ),
                ),
            ],
            ),
        ),
        );
    }

    Widget _buildCoverPlaceholder(ThemeData theme) {
        return Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.image_outlined, size: 48)),
        );
    }
}
