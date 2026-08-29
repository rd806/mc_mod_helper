import 'package:flutter/material.dart';

import '../models/mod.dart';
import '../api/mcmod.dart';
import '../widgets/error_view.dart';
import '../widgets/mod_tile.dart';

/// 搜索页:按关键词搜索模组,点击结果进入详情页
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

    @override
    void dispose() {
        _controller.dispose();
        super.dispose();
    }

    Future<void> _search(String keyword) async {
        keyword = keyword.trim();
        if (keyword.isEmpty) {
            // 空关键词:回到未搜索状态
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
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('MC百科 · 模组搜索'),
            ),
            body: Column(
            children: [
                Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    onChanged: (text) {
                    // 清空输入时回到未搜索状态
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
                Expanded(child: _buildSearchBody()),
            ],
            ),
        );
    }

    Widget _buildSearchBody() {
        if (!_hasSearched) {
        return Center(
            child: Text(
            '输入模组名 / 英文名 / 缩写开始搜索',
            style: Theme.of(context).textTheme.bodyLarge,
            ),
        );
        }
        if (_searching) {
        return const Center(child: CircularProgressIndicator());
        }
        if (_searchError != null) {
        return ErrorView(
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
        itemBuilder: (context, index) => ModTile(mod: _results[index]),
        );
    }
}
