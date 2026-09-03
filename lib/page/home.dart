import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';

import '../api/mcmod.dart';
import '../model/mod_category.dart';
import '../model/mod_summary.dart';
import '../service/settings.dart';
import '../widget/captcha_dialog.dart';
import '../widget/category/category.dart';
import '../widget/error_view.dart';
import '../widget/mod/mod_tile.dart';
import 'config.dart';
import 'search.dart';

/// 应用主页:展示 mcmod.cn 首页的模组分类与首页推荐模组列表
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 推荐区状态
  bool _featuredLoading = true;
  String? _featuredError;
  List<ModSummary> _featured = const [];

  // 分类区状态
  bool _categoriesLoading = true;
  String? _categoriesError;
  List<ModCategory> _categories = const [];

  /// 上次发起推荐加载时使用的条数上限,用于判断设置变化是否需要重新拉取
  int? _lastFeaturedLimit;

  /// 上次发起推荐加载时使用的来源(最新收录/最新编辑)
  String? _lastFeaturedSource;

  /// 上次加载分类时使用的数据来源,用于判断设置变化是否需要重新拉取
  ModSource? _lastDataSource;

  /// 推荐请求序号:丢弃过期响应,防止快速切换排序/条数时旧结果覆盖新结果
  int _featuredSeq = 0;

  @override
  void initState() {
    super.initState();
    // 推荐条数上限变化时需要重新拉取(其余设置由 MaterialApp 顶层响应)
    SettingsService.instance.addListener(_onSettingsChanged);
    // 两个请求共用节流,推荐请求会自动约 1 秒后发出
    _loadCategories();
    _loadFeatured();
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 设置变化回调:数据来源变化重拉分类,推荐条数上限/来源变化重拉推荐。
  /// 主题/字体/强调色变化也会触发本回调,但比较后直接返回
  void _onSettingsChanged() {
    if (SettingsService.instance.dataSource != _lastDataSource) {
      _loadCategories();
    }
    if (SettingsService.instance.featuredMax != _lastFeaturedLimit ||
        SettingsService.instance.featuredSource != _lastFeaturedSource) {
      _loadFeatured();
    }
  }

  /// 加载首页推荐列表。[silent] 为 true 时不显示加载动画(下拉刷新用)
  Future<void> _loadFeatured({bool silent = false}) async {
    final limit = SettingsService.instance.featuredMax;
    final source = SettingsService.instance.featuredSource;
    final seq = ++_featuredSeq;
    if (!silent) {
      setState(() {
        _featuredLoading = true;
        _featuredError = null;
      });
    }
    // 在发起时记录本次使用的上限与来源:加载期间再变化会再次触发重载
    _lastFeaturedLimit = limit;
    _lastFeaturedSource = source;
    try {
      final mods = await McmodApi.getFeaturedMods(sort: source, limit: limit);
      if (!mounted || seq != _featuredSeq) return;
      setState(() {
        _featured = mods;
        _featuredLoading = false;
        _featuredError = null;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted || seq != _featuredSeq) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted || seq != _featuredSeq) return;
      if (!ok) {
        setState(() {
          _featuredError = e.toString();
          _featuredLoading = false;
        });
        return;
      }
      await _loadFeatured(silent: silent);
    } catch (e) {
      if (!mounted || seq != _featuredSeq) return;
      setState(() {
        _featuredError = e.toString();
        _featuredLoading = false;
      });
    }
  }

  /// 加载首页模组分类(按数据来源选择平台)。
  /// [silent] 为 true 时不显示加载动画(下拉刷新用)
  Future<void> _loadCategories({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _categoriesLoading = true;
        _categoriesError = null;
      });
    }
    // 在发起时记录使用的数据来源:加载期间再变化会再次触发重载
    final dataSource = SettingsService.instance.dataSource;
    _lastDataSource = dataSource;
    try {
      // 注意 await:返回值是 Future,未等待会变成未处理的异步错误,
      // 且后续强转会失败
      final cats = await SourceManager.getCategory(dataSource);
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoriesLoading = false;
        _categoriesError = null;
      });
    } on McmodCaptchaException catch (e) {
      if (!mounted) return;
      final ok = await resolveCaptcha(context, e.challenge);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _categoriesError = e.toString();
          _categoriesLoading = false;
        });
        return;
      }
      await _loadCategories(silent: silent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesError = e.toString();
        _categoriesLoading = false;
      });
    }
  }

  /// 重新加载本页:分类与推荐两个区块同时刷新(非静默,显示加载动画)
  Future<void> _refresh() async {
    await Future.wait([_loadCategories(), _loadFeatured()]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶部栏
      appBar: AppBar(
        title: const Text('MC Mod Helper'),
        actions: [
          // 搜索
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          // 设置
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ConfigPage())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          _loadFeatured(silent: true),
          _loadCategories(silent: true),
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          children: [
            _buildSectionTitle('首页推荐', Icons.thumb_up_rounded),
            _buildFeaturedSection(),
            // 分隔线
            const Divider(),
            _buildSectionTitle('模组分类', Icons.widgets_rounded),
            _buildCategoriesSection(),
          ],
        ),
      ),
    );
  }

  /// 构建标题
  Widget _buildSectionTitle(String sectionTitle, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(sectionTitle, style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }

  // ---------- 推荐区 ----------
  Widget _buildFeaturedSection() {
    if (_featuredLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_featuredError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorView(message: _featuredError!, onRetry: _loadFeatured),
      );
    }
    return Column(children: [for (final mod in _featured) ModTile(mod: mod)]);
  }

  // ---------- 分类区 ----------
  Widget _buildCategoriesSection() {
    // 加载动画
    if (_categoriesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 加载错误
    if (_categoriesError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorView(message: _categoriesError!, onRetry: _loadCategories),
      );
    }
    // 正确内容
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏：每个分类卡片占一行,纵向排列
        if (constraints.maxWidth < 480) {
          return Column(
            children: [
              for (final cat in _categories) CategoryCard(category: cat),
            ],
          );
        }
        // 宽屏
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // 固定高度的卡片
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent (
            maxCrossAxisExtent: 300,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // 卡片高度 = 宽度 / 纵横比
            childAspectRatio: 3.0,
          ),
          children: [
            for (final cat in _categories) CategoryCard(category: cat),
          ],
        );
      },
    );
  }
}
