import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';
import 'package:mc_mod_helper/widget/link_icons.dart';

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

  /// 搜索状态
  bool _searching = false;
  bool _hasSearched = false;
  String? _searchError;

  /// 聚合搜索覆盖的来源
  final List<ModSource> _source = const [ModSource.mcmod, ModSource.modrinth];

  /// 各来源搜索结果(仅成功来源,空列表也正常收录)
  Map<ModSource, List<ModSummary>> _totalResults = const {};

  /// 失败来源的错误信息
  Map<ModSource, String> _sourceErrors = const {};

  /// 当前展示的来源
  ModSource _selectedSource = ModSource.mcmod;

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
      // 聚合搜索:并发请求全部来源,单个来源失败不影响其它来源
      final total = await SourceManager.getTotalSearch(_source, keyword);

      if (!mounted) return;
      setState(() {
        _totalResults = total.results;
        _sourceErrors = total.errors;
        _selectedSource = _defaultSource();
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
    // 显示搜索结果:左栏来源切换,右栏当前来源的结果
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏:来源切换(高亮当前来源,标注结果条数/失败)
        Expanded(
          flex: 1,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _source.length,
            itemBuilder: (context, index) => _buildSourceButton(index),
          ),
        ),
        // 右栏:当前来源的搜索结果
        Expanded(flex: 3, child: _showResults()),
      ],
    );
  }

  /// 搜索完成后默认展示的来源:优先设置的数据来源;
  /// 其失败或无结果时,回落到列表顺序里第一个有结果的来源
  ModSource _defaultSource() {
    final preferred = SettingsService.instance.dataSource;
    final preferredMods = _totalResults[preferred];
    if (preferredMods != null && preferredMods.isNotEmpty) return preferred;
    for (final source in _source) {
      final mods = _totalResults[source];
      if (mods != null && mods.isNotEmpty) return source;
    }
    // 都没有结果:优先展示设置来源的错误/空态
    return _totalResults.containsKey(preferred) ? preferred : _source.first;
  }

  /// 左栏来源按钮
  Widget _buildSourceButton(int index) {
    final theme = Theme.of(context);
    final source = _source[index];
    final selected = source == _selectedSource;
    final icon = LinkIcons.getIconForDataSource(source);
    final label = _sourceErrors.containsKey(source)
        ? '${SourceManager.getSourceString(source)} · 失败'
        : '${SourceManager.getSourceString(source)} (${_totalResults[source]?.length ?? 0})';
    return TextButton(
      onPressed: () => _setDisplayResults(index),
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface,
        textStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 16, 3, 16),
        child: Chip(
          avatar: Icon(icon),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  /// 切换展示的来源(必须 setState,否则右栏不会重建)
  void _setDisplayResults(int index) {
    setState(() => _selectedSource = _source[index]);
  }

  /// 右栏:当前来源的搜索结果;来源失败时展示该来源的错误与重试
  Widget _showResults() {
    final error = _sourceErrors[_selectedSource];
    if (error != null) {
      return ErrorView(
        message: error,
        onRetry: () => _search(_controller.text),
      );
    }
    final result = _totalResults[_selectedSource] ?? const [];
    if (result.isEmpty) {
      return Center(
        child: Text('没有找到相关模组', style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: result.length,
      itemBuilder: (context, index) => ModTile(mod: result[index]),
    );
  }
}
