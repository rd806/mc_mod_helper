import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/source.dart';

import '../../api/mcmod.dart';
import '../../model/mod/mod_summary.dart';
import '../../setting/display_settings.dart';
import '../../widget/handler/captcha_dialog.dart';
import '../../widget/common/error_view.dart';

/// 版块模组列表页(默认排序 / 最新收录 / 最新编辑):
/// 与分类页同一套加载方式——滚到底自动加载下一页。
///
/// 三个版块的差别只有 [source](排序方式)与标题,故共用这一个页面,
/// 由 default_list.dart / last_publish_list.dart / last_edit_list.dart 分别包一层。
class FeatureListPage extends StatefulWidget {
  const FeatureListPage({super.key, required this.source, required this.title});

  /// 排序方式(默认排序/最新收录/最新编辑)
  final FeatureSource source;

  /// 页面标题
  final String title;

  @override
  State<FeatureListPage> createState() => _FeatureListPageState();
}

class _FeatureListPageState extends State<FeatureListPage> {
  final ScrollController _controller = ScrollController();

  final List<ModSummary> _mods = [];

  /// 请求序号:丢弃过期响应
  int _seq = 0;

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

  /// 按当前数据来源拉取第 [page] 页
  Future<({List<ModSummary> mods, int totalPages})> _fetchPage(int page) {
    return SourceManager.getFeaturePage(
      DisplaySettings.instance.dataSource,
      widget.source,
      page,
    );
  }

  /// 加载第一页
  Future<void> _loadInitial() async {
    final seq = ++_seq;
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final result = await _fetchPage(1);
      if (!mounted || seq != _seq) return;
      setState(() {
        _mods
          ..clear()
          ..addAll(result.mods);
        _page = 1;
        _totalPages = result.totalPages;
        _initialLoading = false;
        _loadMoreFailed = false;
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
      await _loadInitial();
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
    if (_loading || _loadMoreFailed || !_hasMore || _initialLoading) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final result = await _fetchPage(_page + 1);
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
        setState(() {
          _error = e.toString();
          _initialLoading = false;
        });
        return;
      }
      await _loadInitial();
    } catch (_) {
      // 保留已加载内容,尾部显示重试
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadMoreFailed = true;
      });
    }
  }

  /// 重新加载本页:重新拉取第 1 页
  Future<void> _refresh() async {
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _loadInitial);
    }
    if (_mods.isEmpty) {
      return const Center(child: Text('暂无模组'));
    }
    // 按设置的展示方式渲染(卡片/列表/自适应),监听设置即时切换
    return ListenableBuilder(
      listenable: DisplaySettings.instance,
      builder: (context, _) => CustomScrollView(
        controller: _controller,
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
    final theme = Theme.of(context);
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
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
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
