import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';

import '../api/mcmod.dart';
import '../model/mod_summary.dart';
import '../service/settings.dart';
import '../widget/captcha_dialog.dart';
import '../widget/error_view.dart';
import '../widget/mod/mod_tile.dart';

/// 搜索页：按关键词搜索模组，点击结果进入详情页
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
      // 按设置的数据来源选择搜索平台(提交时读取,切来源后重搜即生效)
      final results = await SourceManager.getSearch(
        SettingsService.instance.dataSource,
        keyword,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _searchError = e.toString();
          _searching = false;
        });
        return;
      }
      // 解除入口锁后重试(弹窗期间 UI 被模态挡住,无重入风险)
      _searching = false;
      await _search(keyword);
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
      appBar: AppBar(title: const Text('模组搜索')),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildSearchBody()),
        ],
      ),
    );
  }

  // 输入栏
  Widget _buildSearchBar() {
    return Padding(
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
          hintText: '输入模组名 / 英文名 / 缩写',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => _search(_controller.text),
          ),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
    );
  }

  // 搜索区
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
        child: Text('没有找到相关模组', style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    // 显示搜索结果，不使用分隔线
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _results.length,
      itemBuilder: (context, index) => ModTile(mod: _results[index]),
    );
  }
}
