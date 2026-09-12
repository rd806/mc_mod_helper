import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

import '../../api/mcmod.dart';
import '../../model/mod/mod_summary.dart';
import '../../widget/handler/captcha_dialog.dart';
import '../../widget/common/error_view.dart';
import '../feature/default_list.dart';
import '../feature/last_edit_list.dart';
import '../feature/last_publish_list.dart';
import '../more/config.dart';

/// 首页每个版块展示的条数(更多的点「查看更多」进列表页)
const int _sectionLimit = 5;

/// 首页:三个版块各展示 [_sectionLimit] 条,
/// 「查看更多」进入该版块的完整列表页(滚到底自动加载下一页)
class FeaturePage extends StatefulWidget {
  const FeaturePage({super.key});

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

/// 首页一个版块的状态:排序方式 + 该版块的模组/加载/错误
class _FeatureSection {
  _FeatureSection(this.source, this.icon);

  final FeatureSource source;
  final IconData icon;

  String get title => SourceManager.getFeatureTitle(source);

  bool loading = true;
  String? error;
  List<ModSummary> mods = const [];
}

class _FeaturePageState extends State<FeaturePage> {
  final List<_FeatureSection> _sections = [
    _FeatureSection(FeatureSource.none, Icons.thumb_up_rounded),
    _FeatureSection(FeatureSource.createTime, Icons.fiber_new_rounded),
    _FeatureSection(FeatureSource.lastEditTime, Icons.edit_note_rounded),
  ];

  /// 上次加载使用的数据来源,用于判断设置变化是否需要重新拉取
  ModSource? _lastDataSource;

  /// 上次构建时使用的展示方式,变化时仅重建(不重新拉取)
  DisplayStyle? _lastDisplayStyle;

  /// 加载序号:丢弃过期响应(重试/切换来源时旧结果不再覆盖新结果)
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    // 数据来源变化要重拉;展示方式变化只换布局
    // (主题等界面设置由 MaterialApp 顶层响应)
    DisplaySettings.instance.addListener(_onSettingsChanged);
    _loadAll();
  }

  @override
  void dispose() {
    DisplaySettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (DisplaySettings.instance.displayStyle != _lastDisplayStyle) {
      setState(() => _lastDisplayStyle = DisplaySettings.instance.displayStyle);
    }
    if (DisplaySettings.instance.dataSource != _lastDataSource) {
      _loadAll();
    }
  }

  /// 依次加载三个版块。
  ///
  /// 顺序而不是并发:各请求共用来源自己的节流间隔,并发发出会互相插队
  /// (先发的还没记录时间戳,后发的算不出间隔)。每块加载完立即刷新界面。
  Future<void> _loadAll({bool silent = false}) async {
    final seq = ++_seq;
    _lastDataSource = DisplaySettings.instance.dataSource;
    if (!silent) {
      setState(() {
        for (final section in _sections) {
          section.loading = true;
          section.error = null;
        }
      });
    }
    for (final section in _sections) {
      // 已被新的加载(重试/切换来源)取代:后面的版块交给它
      if (!mounted || seq != _seq) return;
      await _loadSection(section, seq, silent: silent);
    }
  }

  /// 加载单个版块。[silent] 为 true 时不显示加载动画(下拉刷新用)
  Future<void> _loadSection(
    _FeatureSection section,
    int seq, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        section.loading = true;
        section.error = null;
      });
    }
    try {
      final mods = await SourceManager.getFeature(
        DisplaySettings.instance.dataSource,
        section.source,
        _sectionLimit,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        section.mods = mods;
        section.loading = false;
        section.error = null;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted || seq != _seq) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted || seq != _seq) return;
      if (!ok) {
        setState(() {
          section.error = e.toString();
          section.loading = false;
        });
        return;
      }
      // 验证码通过:三个版块整组重试(已抓页有缓存,重试开销很小)
      await _loadAll(silent: silent);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        section.error = e.toString();
        section.loading = false;
      });
    }
  }

  /// 重新加载本页(非静默,显示加载动画)
  Future<void> _refresh() => _loadAll();

  /// 「查看更多」:进入该版块的完整列表页(滚到底加载下一页)
  void _openMore(_FeatureSection section) {
    final page = switch (section.source) {
      FeatureSource.none => const DefaultModPage(),
      FeatureSource.createTime => const LastPublishModPage(),
      FeatureSource.lastEditTime => const LastEditModPage(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MC Mod Helper'),
        actions: [
          // 刷新
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          // 设置
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ConfigPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadAll(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [for (final section in _sections) _buildSection(section)],
        ),
      ),
    );
  }

  /// 一个版块:标题行(图标 + 名称 + 查看更多) + 模组列表
  Widget _buildSection(_FeatureSection section) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 0, 4),
          child: Row(
            children: [
              Icon(section.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(section.title, style: theme.textTheme.titleLarge),
              ),
              TextButton(
                onPressed: () => _openMore(section),
                child: const Text('查看更多'),
              ),
            ],
          ),
        ),
        _buildSectionBody(section),
        const Divider(height: 16),
      ],
    );
  }

  Widget _buildSectionBody(_FeatureSection section) {
    if (section.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (section.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ErrorView(message: section.error!, onRetry: () => _loadAll()),
      );
    }
    if (section.mods.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('暂无模组')),
      );
    }
    // 按设置展示方式渲染(卡片/列表/自适应);嵌套在页面 ListView 里,
    // shrinkWrap + 禁滚,滚动由外层接管
    return CustomScrollView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 4),
          sliver: DisplayManager.buildSliver(
            DisplaySettings.instance.displayStyle,
            section.mods,
          ),
        ),
      ],
    );
  }
}
