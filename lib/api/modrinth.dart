import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;

import '../model/mod_category.dart';
import '../model/mod_detail.dart';
import '../model/mod_link.dart';
import '../model/mod_summary.dart';

/// Modrinth(modrinth.com)数据获取服务。
///
/// 官方公开 API(api.modrinth.com/v2),无需鉴权,
/// 但必须携带 User-Agent,否则返回 429。
class ModrinthApi {
  ModrinthApi._();

  /// 测试可替换的客户端工厂(测试中用 MockClient 注入假响应)
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= clientFactory();

  static const Map<String, String> _headers = {
    'User-Agent': 'MCModHelper/1.0.0',
  };

  /// 请求最小间隔(礼貌限速;与 McmodApi 的节流互相独立)
  static const Duration _minInterval = Duration(seconds: 1);
  static DateTime? _lastAt;

  /// 会话缓存,避免重复请求
  static final Map<String, List<ModSummary>> _searchCache = {};
  static final Map<String, ModDetail> _detailCache = {};
  static List<ModCategory>? _categoryCache;
  static final Map<String, ({List<ModSummary> mods, int totalPages})>
      _categoryModsCache = {};

  @visibleForTesting
  static void clearCaches() {
    _searchCache.clear();
    _detailCache.clear();
    _categoryCache = null;
    _categoryModsCache.clear();
    _lastAt = null;
    // 重置惰性缓存的客户端,让测试可以替换 clientFactory
    _clientInstance = null;
  }

  /// 按关键词搜索模组,返回摘要列表。
  ///
  /// index=relevance 的返回顺序即相关度排序,不需要再做重排。
  static Future<List<ModSummary>> search(String keyword) async {
    final cached = _searchCache[keyword];
    if (cached != null) return cached;

    // facets 要求 URL 编码的 JSON,Uri.replace 会自动编码方括号
    final uri = Uri.parse('https://api.modrinth.com/v2/search').replace(
      queryParameters: {
        'query': keyword,
        'limit': '20',
        'index': 'relevance',
        'facets': '[["project_type:mod"]]',
      },
    );
    final body = await _get(uri);
    final results = _parseSearch(body);
    _searchCache[keyword] = results;
    return results;
  }

  /// 获取模组详情。[sourceId] 为项目 slug(如 'jei')或项目 id。
  ///
  /// [fallbackDescription] 用于正文为空时回退(通常来自搜索结果)。
  static Future<ModDetail> getDetail(
    String sourceId, {
    String? fallbackDescription,
  }) async {
    final cached = _detailCache[sourceId];
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.modrinth.com/v2/project/$sourceId');
    final body = await _get(uri);
    final detail = _parseDetail(
      body,
      sourceId: sourceId,
      fallbackDescription: fallbackDescription,
    );
    _detailCache[sourceId] = detail;
    return detail;
  }

  /// 获取详情页所属分类之外的公开接口:模组分类列表。
  ///
  /// Modrinth 的 tag/category 接口返回全部分类(含资源包分辨率、加载器等),
  /// 这里只保留 project_type=mod 的 categories 组。
  static Future<List<ModCategory>> getCategories() async {
    final cached = _categoryCache;
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.modrinth.com/v2/tag/category');
    final body = await _get(uri);
    final cats = _parseCategories(body);
    _categoryCache = cats;
    return cats;
  }

  /// 获取分类下第 [page] 页的模组(每页 20 个)与总页数。
  ///
  /// 用 search 接口按 categories facet 过滤,index=downloads 按下载量排序;
  /// 分页是 offset 制,(page-1)*20 换算。
  static Future<({List<ModSummary> mods, int totalPages})> getCategoryMods(
    String categoryName, {
    int page = 1,
  }) async {
    final key = '$categoryName-$page';
    final cached = _categoryModsCache[key];
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.modrinth.com/v2/search').replace(
      queryParameters: {
        'limit': '20',
        'offset': '${(page - 1) * 20}',
        'index': 'downloads',
        'facets': '[["categories:$categoryName"],["project_type:mod"]]',
      },
    );
    final body = await _get(uri);
    final result = _parseCategoryPage(body);
    _categoryModsCache[key] = result;
    return result;
  }

  // ---------- 请求基础 ----------

  /// 抓取 JSON 并解码为文本,保证与上次请求至少间隔 [_minInterval]
  static Future<String> _get(Uri uri) async {
    if (_lastAt != null) {
      final elapsed = DateTime.now().difference(_lastAt!);
      if (elapsed < _minInterval) {
        await Future<void>.delayed(_minInterval - elapsed);
      }
    }
    _lastAt = DateTime.now();
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('请求失败: HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  // ---------- 解析 ----------

  static List<ModSummary> _parseSearch(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final hits = (data['hits'] as List<dynamic>? ?? const []);
    return [
      for (final hit in hits.cast<Map<String, dynamic>>()) ?_parseHit(hit),
    ];
  }

  /// 单个搜索命中条目 → ModSummary;字段缺失时返回 null 丢弃
  static ModSummary? _parseHit(Map<String, dynamic> hit) {
    final slug = (hit['slug'] as String?)?.trim() ?? '';
    final title = (hit['title'] as String?)?.trim() ?? '';
    if (slug.isEmpty || title.isEmpty) return null;
    return ModSummary(
      id: slug,
      title: title,
      description: (hit['description'] as String?) ?? '',
      iconUrl: hit['icon_url'] as String?,
      statsText: _buildStats(
        (hit['downloads'] as num?)?.toInt(),
        (hit['follows'] as num?)?.toInt(),
      ),
      source: 'modrinth',
    );
  }

  /// 分类 slug → 中文名(应用为中文 UI,未收录的保留原文)
  static const Map<String, String> _categoryNames = {
    'adventure': '冒险',
    'cursed': '趣味',
    'decoration': '装饰',
    'economy': '经济',
    'equipment': '装备',
    'food': '食物',
    'game-mechanics': '玩法机制',
    'library': '前置库',
    'magic': '魔法',
    'management': '经营',
    'minigame': '小游戏',
    'mobs': '生物',
    'optimization': '优化',
    'social': '社交',
    'storage': '存储',
    'technology': '科技',
    'transportation': '交通',
    'utility': '实用',
    'worldgen': '世界生成',
  };

  static List<ModCategory> _parseCategories(String body) {
    final data = jsonDecode(body) as List<dynamic>;
    final cats = <ModCategory>[];
    for (final item in data.cast<Map<String, dynamic>>()) {
      if (item['project_type'] != 'mod') continue;
      if (item['header'] != 'categories') continue;
      final slug = (item['name'] as String?)?.trim() ?? '';
      if (slug.isEmpty) continue;
      cats.add(
        ModCategory(
          id: slug,
          name: _categoryNames[slug] ?? slug,
          source: 'modrinth',
        ),
      );
    }
    return cats;
  }

  static ({List<ModSummary> mods, int totalPages}) _parseCategoryPage(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final hits = (data['hits'] as List<dynamic>? ?? const []);
    final mods = [
      for (final hit in hits.cast<Map<String, dynamic>>()) ?_parseHit(hit),
    ];
    final totalHits = (data['total_hits'] as num?)?.toInt() ?? mods.length;
    final totalPages = totalHits <= 0 ? 0 : (totalHits + 19) ~/ 20;
    return (mods: mods, totalPages: totalPages);
  }

  static ModDetail _parseDetail(
    String body, {
    required String sourceId,
    String? fallbackDescription,
  }) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final title = (data['title'] as String?)?.trim() ?? '';
    final markdown =
        (data['body'] as String?)?.trim() ??
        (fallbackDescription ?? (data['description'] as String?) ?? '');
    final html = _markdownToHtml(markdown);

    return ModDetail(
      id: sourceId,
      title: title,
      subName: null,
      description: html.isEmpty ? null : html,
      coverUrl: data['icon_url'] as String?,
      links: _buildLinks(data),
      mcVersions: (data['game_versions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      platform: _buildPlatform(data),
      environment: _buildEnvironment(data),
      source: 'modrinth',
    );
  }

  /// 相关链接:源码/问题反馈/Wiki/Discord/捐赠
  static List<ModLink> _buildLinks(Map<String, dynamic> data) {
    final links = <ModLink>[];
    void add(String name, String? url) {
      if (url != null && url.isNotEmpty) links.add(ModLink(name: name, url: url));
    }

    final source = data['source_url'] as String?;
    // 名称带品牌关键词,以命中详情页 _linkIcon 的品牌图标
    add(source != null && source.contains('github') ? 'GitHub' : '源代码', source);
    final issues = data['issues_url'] as String?;
    add(
      issues != null && issues.contains('github') ? 'GitHub Issues' : '问题反馈',
      issues,
    );
    add('Wiki', data['wiki_url'] as String?);
    add('Discord', data['discord_url'] as String?);
    const donationNames = {
      'patreon': 'Patreon',
      'bmac': 'Buy Me a Coffee',
      'ko-fi': 'Ko-fi',
      'paypal': 'PayPal',
      'github': 'GitHub 赞助',
    };
    for (final d in (data['donation_urls'] as List<dynamic>? ?? const [])) {
      if (d is! Map<String, dynamic>) continue;
      final platform = d['platform'] as String? ?? '';
      final url = d['url'] as String?;
      add(donationNames[platform] ?? platform, url);
    }
    return links;
  }

  /// 支持平台:由 loaders 拼接,如 'Fabric / NeoForge'
  static String? _buildPlatform(Map<String, dynamic> data) {
    final loaders = (data['loaders'] as List<dynamic>? ?? const [])
        .cast<String>()
        .map((l) => l.isEmpty
            ? l
            : '${l[0].toUpperCase()}${l.substring(1).toLowerCase()}')
        .toList();
    return loaders.isEmpty ? null : loaders.join(' / ');
  }

  /// 运行环境:(client_side, server_side) 组合 → 中文,未知组合不显示
  static const Map<String, String> _envMap = {
    'required|required': '客户端与服务端',
    'required|optional': '客户端（服务端可选）',
    'required|unsupported': '仅客户端',
    'optional|required': '服务端（客户端可选）',
    'optional|optional': '客户端与服务端（可选）',
    'optional|unsupported': '仅客户端（可选）',
    'unsupported|required': '仅服务端',
    'unsupported|optional': '仅服务端（可选）',
  };

  static String? _buildEnvironment(Map<String, dynamic> data) {
    final client = data['client_side'] as String?;
    final server = data['server_side'] as String?;
    if (client == null || server == null) return null;
    return _envMap['$client|$server'];
  }

  /// 统计文本:如 '下载 7385.6万 · 关注 1.1万'
  static String? _buildStats(int? downloads, int? follows) {
    final parts = <String>[
      if (downloads != null && downloads > 0) '下载 ${_formatCount(downloads)}',
      if (follows != null && follows > 0) '关注 ${_formatCount(follows)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 数字格式化为 万/亿(保留 1 位小数,整数时去掉 .0)
  static String _formatCount(int n) {
    String trim(String s) => s.replaceFirst(RegExp(r'\.0$'), '');
    if (n >= 100000000) return '${trim((n / 100000000).toStringAsFixed(1))}亿';
    if (n >= 10000) return '${trim((n / 10000).toStringAsFixed(1))}万';
    return '$n';
  }

  /// Markdown 正文转成适合 app 内渲染的 HTML。
  ///
  /// 复用详情页现有 HtmlWidget 渲染链:图片包 <a> 链接以走灯箱、
  /// 表格补边框(与 mcmod 清洗一致的 fwfh 处理)。
  static String _markdownToHtml(String markdown) {
    var html = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    // markdown 包对原生 HTML 的透传行为各版本有差异,剥掉兜底
    html = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<iframe[^>]*>.*?</iframe>', dotAll: true), '');
    // 图片:限制最大宽度 + 包一层链接,点击时在灯箱中放大查看
    html = html.replaceAllMapped(RegExp(r'<img([^>]*)>'), (m) {
      final attrs = m.group(1)!;
      final src = RegExp(r'src="([^"]*)"').firstMatch(attrs)?.group(1);
      final img = '<img$attrs style="max-width:100%">';
      return (src == null || src.isEmpty) ? img : '<a href="$src">$img</a>';
    });
    // 表格统一处理:
    // - 含图片的表格(画廊等):保留真实表格布局(已验证 fwfh 0.17
    //   可正常渲染图片单元格),只清理固定宽度;不加边框保持画廊观感。
    // - 纯文字表格:清理固定宽度后补边框、合并为单线、表头居中。
    html = html.replaceAllMapped(
      RegExp(r'<table[^>]*>.*?</table>', dotAll: true),
      (m) {
        final block = m.group(0)!;
        var table = block
            .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
            .replaceAll(RegExp(r'\s+style="[^"]*"'), '');
        if (table.contains('<img')) {
          // 剥离 valign:fwfh 会为带 valign 的单元格包 ValignBaseline,
          // 其在 paint 阶段计算 dry-baseline,而 RenderImage.paint 会访问
          // size,触发 'renderBoxDoingDryBaseline' 断言(图片画廊必崩);
          // 画廊图片高度统一,不再需要垂直对齐
          table = table.replaceAll(RegExp(r'\s+valign="[^"]*"'), '');
          // 画廊图片注入固定高度:fwfh 的 CssSizing 会把高度收紧,
          // 图片加载完成前就占据固定行高,且自动钳制在单元格宽度内
          // (不像 width/height 属性的 AspectRatio 盒会无视单元格约束);
          // 加载时只变化宽度,不引起纵向布局移动
          // (悬停处布局移动会触发 Flutter MouseTracker 的 debug 断言)
          return table.replaceAllMapped(RegExp(r'<img([^>]*)>'), (m) {
            var attrs = m.group(1)!;
            attrs = attrs
                .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
                .replaceAll(RegExp(r'\s+height="[^"]*"'), '')
                .replaceAll(RegExp(r'\s+style="[^"]*"'), '');
            return '<img$attrs>';
          });
        }
        if (!RegExp(r'<table[^>]*\sborder="0"').hasMatch(table)) {
          final borderAttr = RegExp(r'<table[^>]*\sborder=').hasMatch(table)
              ? ''
              : ' border="1"';
          return table
              .replaceFirst(
                RegExp(r'<table'),
                '<table style="border-collapse:collapse"$borderAttr',
              )
              .replaceAllMapped(RegExp(r'<th([^>]*)>'), (m) {
                return '<th${m.group(1)!} style="text-align:center">';
              });
        }
        return table;
      },
    );
    return html;
  }
}
