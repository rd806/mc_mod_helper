import 'package:flutter/material.dart';

import '../models/mod.dart';
import '../services/mcmod_api.dart';
import 'detail_page.dart';

/// 应用主页:默认展示 mcmod.cn 首页推荐(最新收录/最新编辑)的模组,支持搜索
class SearchPage extends StatefulWidget {
    const SearchPage({super.key});

    @override
    State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
    final TextEditingController _controller = TextEditingController();

    // 搜索状态
    bool _searching = false;
    String? _searchError;
    List<ModSummary> _results = const [];
    bool _hasSearched = false;

    // 首页推荐状态
    bool _featuredLoading = true;
    String? _featuredError;
    List<ModSummary> _featured = const [];
    String _featuredSort = 'createtime';

    @override
    void initState() {
        super.initState();
        _loadFeatured();
    }

    /// 加载首页推荐列表。[silent] 为 true 时不显示整页加载动画(下拉刷新用)
    Future<void> _loadFeatured({bool silent = false}) async {
        if (!silent) {
        setState(() {
            _featuredLoading = true;
            _featuredError = null;
        });
        }
        try {
        final mods = await McmodApi.getFeaturedMods(sort: _featuredSort);
        if (!mounted) return;
        setState(() {
            _featured = mods;
            _featuredLoading = false;
            _featuredError = null;
        });
        } catch (e) {
        if (!mounted) return;
        setState(() {
            _featuredError = e.toString();
            _featuredLoading = false;
        });
        }
    }

    Future<void> _search(String keyword) async {
        keyword = keyword.trim();
        if (keyword.isEmpty) {
        // 空关键词:回到首页推荐
        setState(() => _hasSearched = false);
        return;
        }
        if (_searching) return;
        setState(() {
        _searching = true;
        _hasSearched = true;
        _searchError = null;
        });
        try {
        final results = await McmodApi.search(keyword);
        if (!mounted) return;
        setState(() {
            _results = results;
            _searching = false;
        });
        } catch (e) {
        if (!mounted) return;
        setState(() {
            _searchError = e.toString();
            _searching = false;
        });
        }
    }

    @override
    void dispose() {
        _controller.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
        appBar: AppBar(title: const Text('MC百科 · 模组搜索')),
        body: Column(
            children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                onChanged: (text) {
                    // 清空输入时回到首页推荐
                    if (text.trim().isEmpty && _hasSearched) {
                    setState(() => _hasSearched = false);
                    }
                },
                decoration: InputDecoration(
                    hintText: '输入模组名 / 英文名 / 缩写,如 JEI',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _search(_controller.text),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    ),
                ),
                ),
            ),
            Expanded(
                child: _hasSearched ? _buildSearchBody() : _buildFeaturedBody(),
            ),
            ],
        ),
        );
    }

    // ---------- 搜索模式 ----------

    Widget _buildSearchBody() {
        if (_searching) {
        return const Center(child: CircularProgressIndicator());
        }
        if (_searchError != null) {
        return _ErrorView(
            message: _searchError!,
            onRetry: () => _search(_controller.text),
        );
        }
        if (_results.isEmpty) {
        return Center(
            child: Text(
            '没有找到相关模组',
            style: Theme.of(context).textTheme.bodyLarge,
            ),
        );
        }
        return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _results.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _ResultTile(mod: _results[index]),
        );
    }

    // ---------- 首页推荐模式 ----------

    Widget _buildFeaturedBody() {
        if (_featuredLoading) {
        return const Center(child: CircularProgressIndicator());
        }
        if (_featuredError != null) {
        return _ErrorView(
            message: _featuredError!,
            onRetry: _loadFeatured,
        );
        }
        return RefreshIndicator(
        onRefresh: () => _loadFeatured(silent: true),
        child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                children: [
                    Expanded(
                    child: Text(
                        '首页推荐',
                        style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ),
                    SegmentedButton<String>(
                    segments: const [
                        ButtonSegment(value: 'createtime', label: Text('最新收录')),
                        ButtonSegment(value: 'lastedittime', label: Text('最新编辑')),
                    ],
                    selected: {_featuredSort},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                    ),
                    onSelectionChanged: (selection) {
                        if (selection.first == _featuredSort) return;
                        setState(() => _featuredSort = selection.first);
                        _loadFeatured();
                    },
                    ),
                ],
                ),
            ),
            for (final mod in _featured) _ResultTile(mod: mod),
            ],
        ),
        );
    }
}

/// 加载失败提示 + 重试
class _ErrorView extends StatelessWidget {
    const _ErrorView({required this.message, required this.onRetry});

    final String message;
    final VoidCallback onRetry;

    @override
    Widget build(BuildContext context) {
        return Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('加载失败\n$message', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
            ),
        ),
        );
    }
}

/// 单条模组(搜索结果 / 首页推荐通用)
class _ResultTile extends StatelessWidget {
    const _ResultTile({required this.mod});

    final ModSummary mod;

    @override
    Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return ListTile(
        leading: _buildAvatar(theme),
        title: Text(
            mod.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
        ),
        subtitle: mod.description.isEmpty
            ? null
            : Text(
                mod.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                ),
        trailing: const Icon(Icons.chevron_right),
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
        );
    }

    /// 有图标就显示图标,加载失败或无图标时回退到首字母头像
    Widget _buildAvatar(ThemeData theme) {
        if (mod.iconUrl != null) {
        return ClipOval(
            child: Image.network(
            mod.iconUrl!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _LetterAvatar(theme: theme, mod: mod),
            ),
        );
        }
        return _LetterAvatar(theme: theme, mod: mod);
    }
}

/// 首字母头像
class _LetterAvatar extends StatelessWidget {
    const _LetterAvatar({required this.theme, required this.mod});

    final ThemeData theme;
    final ModSummary mod;

    @override
    Widget build(BuildContext context) {
        return CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
            (mod.abbr ?? mod.displayName).characters.first.toUpperCase(),
            style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            ),
        ),
        );
    }
}
