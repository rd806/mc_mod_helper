import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:mc_mod_helper/model/project/project_loader.dart';

import '../model/author/author_summary.dart';
import '../model/filter/filter.dart';
import '../model/filter/sort_method.dart';
import '../model/project/project_category.dart';
import '../model/project/project_detail.dart';
import '../model/project/project_type.dart';
import '../model/project/project_version.dart';
import '../model/link.dart';
import '../model/project/project_summary.dart';
import '../setting/value/source.dart';

/// CurseForge(curseforge.com)数据获取服务。
///
/// 官方公开 API(api.curseforge.com/v1),必须携带 API Key。
/// [_apiKey] 是占位符,需要到 CurseForge 开发者中心自行申请替换
/// (官方禁止公开分发 Key,仓库里不应出现真实 Key)。
class CurseforgeApi {
  CurseforgeApi._();

  /// 测试可替换的客户端工厂(测试中用 MockClient 注入假响应)
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= clientFactory();

  /// API Key:占位符不可用,自行申请后替换
  static const String _apiKey = 'YOUR_API_KEY_HERE';

  static Map<String, String> get _headers => {
    'x-api-key': _apiKey,
    'User-Agent': 'MCModHelper/1.0.0',
  };

  /// 请求最小间隔(礼貌限速;与其它 Api 的节流互相独立)
  static const Duration _minInterval = Duration(seconds: 1);
  static DateTime? _lastAt;

  /// 会话缓存,避免重复请求
  static final Map<String, List<ProjectSummary>> _searchCache = {};
  static final Map<String, ProjectDetail> _detailCache = {};
  static List<ProjectCategory>? _categoryCache;

  static List<ProjectVersion>? _versionCache;

  /// 组合筛选的分页缓存:key = '筛选签名|页码'
  static final Map<String, ({List<ProjectSummary> mods, int totalPages})>
  _filteredModsCache = {};

  /// 分页缓存上限(组合筛选的 key 空间大,不能让会话缓存无限堆积)
  static const int _maxCachedQueries = 60;

  /// 写分页缓存,超过上限时先淘汰最早写入的一条
  static void _cacheFiltered(
    Map<String, ({List<ProjectSummary> mods, int totalPages})> cache,
    String key,
    ({List<ProjectSummary> mods, int totalPages}) value,
  ) {
    if (cache.length >= _maxCachedQueries) cache.remove(cache.keys.first);
    cache[key] = value;
  }

  /// Minecraft 游戏 ID(CurseForge 中 Minecraft 的 gameId 固定为 432)
  static const int _gameId = 432;

  /// 模组分类 classId(CurseForge 中模组的 classId 固定为 6)
  static const int _modClassId = 6;

  /// 分类英文名 → 中文名(未收录的保留原文)
  static const Map<String, String> _categoryNames = {
    'Adventure and RPG': '冒险与RPG',
    'Armor, Tools, and Weapons': '装备',
    'Cosmetic': '装饰',
    'Dimensions': '维度',
    'Energy, Fluid, and Item Transport': '能量与物流',
    'Farming': '农业',
    'Food': '食物',
    'Industrial': '工业',
    'Magic': '魔法',
    'Mobs': '生物',
    'Player Transport': '交通',
    'Redstone': '红石',
    'Server Utility': '服务端实用',
    'Storage': '存储',
    'Technology': '科技',
    'Utility & QoL': '实用',
    'World Gen': '世界生成',
    'Map and Information': '地图与信息',
    'Library': '前置库',
    'Education': '教育',
    'Miscellaneous': '杂项',
    'Fabric': 'Fabric',
    'Forge': 'Forge',
    'NeoForge': 'NeoForge',
    'Quilt': 'Quilt',
  };

  @visibleForTesting
  static void clearCaches() {
    _searchCache.clear();
    _detailCache.clear();
    _categoryCache = null;
    _versionCache = null;
    _filteredModsCache.clear();
    _lastAt = null;
    // 重置惰性缓存的客户端,让测试可以替换 clientFactory
    _clientInstance = null;
  }

  /// 按关键词搜索模组,返回摘要列表。
  ///
  /// searchFilter 触发站内相关度排序,返回顺序即相关度顺序。
  static Future<List<ProjectSummary>> search(String keyword) async {
    final cached = _searchCache[keyword];
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.curseforge.com/v1/mods/search').replace(
      queryParameters: {
        'gameId': '$_gameId',
        'classId': '$_modClassId',
        'searchFilter': keyword,
        'pageSize': '20',
        'sortField': '1',
        'sortOrder': 'desc',
      },
    );
    final body = await _get(uri);
    final results = _parseSearch(body);
    _searchCache[keyword] = results;
    return results;
  }

  /// 获取模组详情。[sourceId] 为 CurseForge 的 modId(数字字符串)。
  ///
  /// 详情需要两次请求:模组基本信息 + 文件列表(文件携带版本与加载器)。
  static Future<ProjectDetail> getDetail(
    String sourceId, {
    String? fallbackDescription,
  }) async {
    final cached = _detailCache[sourceId];
    if (cached != null) return cached;

    final modId = int.tryParse(sourceId);
    if (modId == null) {
      throw Exception('无效的 CurseForge ID: $sourceId');
    }

    // 模组基本信息
    final uri = Uri.parse('https://api.curseforge.com/v1/mods/$modId');
    final body = await _get(uri);

    // 文件列表:每个文件带 gameVersions[](版本号与加载器名混在同一列表)
    final filesUri = Uri.parse(
      'https://api.curseforge.com/v1/mods/$modId/files',
    ).replace(queryParameters: {'pageSize': '50', 'sortOrder': 'desc'});
    final filesBody = await _get(filesUri);

    final detail = _parseDetail(
      body,
      filesBody: filesBody,
      sourceId: sourceId,
      fallbackDescription: fallbackDescription,
    );
    _detailCache[sourceId] = detail;
    return detail;
  }

  /// 获取模组分类列表(classId=6 下 Minecraft 的模组分类)
  static Future<List<ProjectCategory>> getCategories() async {
    final cached = _categoryCache;
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.curseforge.com/v1/categories').replace(
      queryParameters: {'gameId': '$_gameId', 'classId': '$_modClassId'},
    );
    final body = await _get(uri);
    final cats = _parseCategories(body);
    _categoryCache = cats;
    return cats;
  }

  /// 获取 Minecraft 版本列表(新版在前)。
  ///
  /// 官方接口给的是全部版本(含快照/预发布),这里只留形如 `1.20.1` 的正式版:
  /// 快照名的形态各异(`1.21-pre1`、`23w31a`…),用「只有数字与点」来筛。
  static Future<List<ProjectVersion>> getVersions() async {
    final cached = _versionCache;
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.curseforge.com/v1/minecraft/version');
    final body = await _get(uri);
    final versions = _parseVersions(body);
    _versionCache = versions;
    return versions;
  }

  /// 组合筛选分页查询:第 [page] 页的模组与总页数。
  ///
  /// 分类 / 版本 / 排序是三个互相独立的搜索参数,可自由组合。
  /// [Filter.category] 的 id 必须是数字(CF 用数字分类 id),
  /// 非数字时返回空结果而不是抛异常(沿用旧行为)。
  /// 分页是 index 偏移制,(page-1)*20 换算。
  static Future<({List<ProjectSummary> mods, int totalPages})> getFilteredMods(
    Filter filter, {
    int page = 1,
  }) async {
    final categoryId = filter.category?.id;
    final id = categoryId == null ? null : int.tryParse(categoryId);
    if (categoryId != null && id == null) {
      return (mods: const <ProjectSummary>[], totalPages: 0);
    }
    final key = '${filter.signature}|$page';
    final cached = _filteredModsCache[key];
    if (cached != null) return cached;

    final uri = Uri.parse('https://api.curseforge.com/v1/mods/search').replace(
      queryParameters: {
        'gameId': '$_gameId',
        'classId': '$_modClassId',
        if (id != null) 'categoryId': '$id',
        if (filter.version != null) 'gameVersion': filter.version!.version,
        'pageSize': '20',
        'index': '${(page - 1) * 20}',
        'sortField': _featuredSortField(filter.sortMethod),
        'sortOrder': 'desc',
      },
    );
    final body = await _get(uri);
    final result = _parseCategoryPage(body);
    _cacheFiltered(_filteredModsCache, key, result);
    return result;
  }

  /// [SortMethod] → ModsSearchSortField 的 sortField
  static String _featuredSortField(SortMethod sort) => switch (sort) {
    SortMethod.none => '1', // Featured(站内精选)
    SortMethod.createTime => '11', // ReleasedDate
    SortMethod.lastEditTime => '3', // LastUpdated
  };

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

  static List<ProjectSummary> _parseSearch(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final mods = (data['data'] as List<dynamic>? ?? const []);
    return [
      for (final mod in mods.cast<Map<String, dynamic>>())
        ?_parseModSummary(mod),
    ];
  }

  /// classId → 项目类型(Minecraft 下:6 模组、4471 整合包、12 材质包、
  /// 6552 光影、5 服务端插件)。表外的 classId(以及字段缺失)按模组处理
  static const Map<int, ProjectType> _classTypes = {
    6: ProjectType.mod,
    4471: ProjectType.modpack,
    12: ProjectType.resourcepack,
    6552: ProjectType.shader,
    5: ProjectType.plugin,
  };

  static ProjectType _projectType(Object? classId) =>
      _classTypes[classId is num ? classId.toInt() : null] ?? ProjectType.mod;

  /// 单个搜索命中条目 → ModSummary;字段缺失时返回 null 丢弃
  static ProjectSummary? _parseModSummary(Map<String, dynamic> mod) {
    final id = (mod['id'] as num?)?.toInt().toString() ?? '';
    final name = (mod['name'] as String?)?.trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final logo = mod['logo'] as Map<String, dynamic>?;
    return ProjectSummary(
      id: id,
      type: _projectType(mod['classId']),
      title: name,
      description: (mod['summary'] as String?) ?? '',
      iconUrl: logo?['url'] as String?,
      statistics: _buildStats(
        (mod['downloadCount'] as num?)?.toInt() ?? 0,
        (mod['followerCount'] as num?)?.toInt() ?? 0,
      ),
      source: ModSource.curseforge,
    );
  }

  static List<ProjectCategory> _parseCategories(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final items = (data['data'] as List<dynamic>? ?? const []);
    final cats = <ProjectCategory>[];
    for (final item in items.cast<Map<String, dynamic>>()) {
      final id = (item['id'] as num?)?.toInt();
      final name = (item['name'] as String?)?.trim() ?? '';
      if (id == null || name.isEmpty) continue;
      cats.add(
        ProjectCategory(
          id: id.toString(),
          type: _projectType(item['classId']),
          name: _categoryNames[name] ?? name,
          source: ModSource.curseforge,
        ),
      );
    }
    return cats;
  }

  /// 解析版本列表:只保留「数字与点」的正式版(快照名形态各异,一并筛掉)
  static List<ProjectVersion> _parseVersions(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final versions = <ProjectVersion>[];
    for (final item
        in (data['data'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()) {
      final version = (item['versionString'] as String?)?.trim() ?? '';
      if (version.isEmpty) continue;
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) continue;
      if (versions.any((v) => v.version == version)) continue;
      versions.add(
        ProjectVersion(version: version, source: ModSource.curseforge),
      );
    }
    return versions;
  }

  static ({List<ProjectSummary> mods, int totalPages}) _parseCategoryPage(
    String body,
  ) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final mods = (data['data'] as List<dynamic>? ?? const []);
    final parsed = <ProjectSummary>[];
    for (final mod in mods.cast<Map<String, dynamic>>()) {
      final summary = _parseModSummary(mod);
      if (summary != null) parsed.add(summary);
    }
    final pagination = data['pagination'] as Map<String, dynamic>?;
    final totalHits =
        (pagination?['totalCount'] as num?)?.toInt() ?? parsed.length;
    final totalPages = totalHits <= 0 ? 0 : (totalHits + 19) ~/ 20;
    return (mods: parsed, totalPages: totalPages);
  }

  static ProjectDetail _parseDetail(
    String body, {
    required String filesBody,
    required String sourceId,
    String? fallbackDescription,
  }) {
    // 注意:详情接口的响应是 {"data": {...}} 信封,先解包
    final data =
        (jsonDecode(body) as Map<String, dynamic>)['data']
            as Map<String, dynamic>? ??
        const {};
    // CurseForge 用 name 而非 title;API 不提供正文 body,
    // 只有 summary 简介(纯文本,走 markdownToHtml 包装成段落)
    final title = (data['name'] as String?)?.trim() ?? '';
    final summary =
        (data['summary'] as String?)?.trim() ?? (fallbackDescription ?? '');
    final html = summary.isEmpty ? '' : _markdownToHtml(summary);
    final logo = data['logo'] as Map<String, dynamic>?;

    return ProjectDetail(
      id: sourceId,
      type: _projectType(data['classId']),
      title: title,
      subName: null,
      body: html.isEmpty ? null : html,
      coverUrl: logo?['url'] as String?,
      links: _buildLinks(data),
      mcVersions: _parseVersionsFromFiles(filesBody),
      platform: _loadersFromFiles(filesBody),
      sides: _parseEnvironment(data),
      source: ModSource.curseforge,
      authors: _parseAuthors(data),
    );
  }

  /// 作者:API 的 authors 列表(id/name/url),无头像与角色信息
  static List<AuthorSummary>? _parseAuthors(Map<String, dynamic> data) {
    final authors = <AuthorSummary>[];
    for (final a in (data['authors'] as List<dynamic>? ?? const [])) {
      if (a is! Map<String, dynamic>) continue;
      final name = (a['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      authors.add(AuthorSummary(name: name));
    }
    return authors.isEmpty ? null : authors;
  }

  /// CurseForge 的加载器名:大小写敏感,写法固定
  static const List<String> _cfLoaders = [
    'Fabric',
    'Forge',
    'NeoForge',
    'Quilt',
  ];

  /// 文件列表 → 加载器 → 版本号 的分组映射。
  ///
  /// CurseForge 文件的 gameVersions 把版本号与加载器名混在同一列表
  /// (如 ['1.21.1', 'Fabric']):含加载器名的按加载器分组,
  /// 版本号(含 '.')收集进对应组;无加载器信息的进 'default'。
  static Map<ProjectLoader, List<String>> _parseVersionsFromFiles(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final files = (data['data'] as List<dynamic>? ?? const []);
    final map = <ProjectLoader, List<String>>{};

    for (final file in files.cast<Map<String, dynamic>>()) {
      final gameVersions = (file['gameVersions'] as List<dynamic>? ?? const [])
          .cast<String>();

      final loaders = [
        for (final v in gameVersions)
          if (_cfLoaders.contains(v)) ProjectLoader.of(v),
      ];

      // 版本号:含 '.' 的条目(加载器名不带点)
      final mcVersions = gameVersions.where((v) => v.contains('.')).toList();

      // 文件没标加载器时归到 'default'(ModLoader 会保留这个名字并给通用图标)
      final targets = loaders.isEmpty ? [ProjectLoader.of('default')] : loaders;
      for (final loader in targets) {
        final list = map.putIfAbsent(loader, () => []);
        for (final v in mcVersions) {
          if (!list.contains(v)) list.add(v);
        }
      }
    }
    return map;
  }

  /// 文件列表 → 支持平台(加载器名,如 'Fabric / NeoForge')
  static String? _loadersFromFiles(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final files = (data['data'] as List<dynamic>? ?? const []);
    final loaders = <String>[];
    for (final file in files.cast<Map<String, dynamic>>()) {
      for (final v in (file['gameVersions'] as List<dynamic>? ?? const [])) {
        if (_cfLoaders.contains(v) && !loaders.contains(v)) loaders.add(v);
      }
    }
    return loaders.isEmpty ? null : loaders.join(' / ');
  }

  /// 运行环境:clientSide/serverSide 布尔 → [客户端, 服务端] 枚举列表。
  ///
  /// 与 ModDetail.environment 的约定一致('required'/'optional'/
  /// 'unsupported');CurseForge 只区分是否支持,true→必需、false→无效,
  /// 字段缺失时返回 null(不显示)
  static List<String>? _parseEnvironment(Map<String, dynamic> data) {
    final clientSide = data['clientSide'] as bool?;
    final serverSide = data['serverSide'] as bool?;
    if (clientSide == null && serverSide == null) return null;
    return [
      if (clientSide != null) (clientSide ? 'required' : 'unsupported'),
      if (serverSide != null) (serverSide ? 'required' : 'unsupported'),
    ];
  }

  /// 相关链接:官网/源码/问题反馈/Wiki(名称带品牌关键词以命中图标)
  static List<Link> _buildLinks(Map<String, dynamic> data) {
    final links = <Link>[];
    void add(String name, String? url) {
      if (url != null && url.isNotEmpty) {
        links.add(Link(icon: Link.getIcon(name), name: name, url: url));
      }
    }

    final linksData = data['links'] as Map<String, dynamic>?;
    if (linksData != null) {
      add('官网', linksData['websiteUrl'] as String?);
      final source = linksData['sourceUrl'] as String?;
      add(
        source != null && source.contains('github') ? 'GitHub' : '源代码',
        source,
      );
      final issues = linksData['issuesUrl'] as String?;
      add(
        issues != null && issues.contains('github') ? 'GitHub Issues' : '问题反馈',
        issues,
      );
      add('Wiki', linksData['wikiUrl'] as String?);
    }
    return links;
  }

  /// 简介纯文本 → HTML(统一走详情页 HTML 渲染管线)
  static String _markdownToHtml(String markdown) {
    var html = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    html = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<iframe[^>]*>.*?</iframe>', dotAll: true), '');
    // 图片:包一层链接,点击时在灯箱中放大查看
    html = html.replaceAllMapped(RegExp(r'<img([^>]*)>'), (m) {
      final attrs = m.group(1)!;
      final src = RegExp(r'src="([^"]*)"').firstMatch(attrs)?.group(1);
      return (src == null || src.isEmpty)
          ? '<img$attrs>'
          : '<a href="$src"><img$attrs></a>';
    });
    return html;
  }

  /// 统计列表:如 [('downloads', '7385.6万'), ('followers', '1.1万')]
  static List<(String, String)>? _buildStats(int downloads, int followers) {
    final parts = <(String, String)>[
      if (downloads > 0) ('downloads', _formatCount(downloads)),
      if (followers > 0) ('followers', _formatCount(followers)),
    ];
    return parts.isEmpty ? null : parts;
  }

  /// 数字格式化为 万/亿(保留 1 位小数,整数时去掉 .0)
  static String _formatCount(int n) {
    String trim(String s) => s.replaceFirst(RegExp(r'\.0$'), '');
    if (n >= 100000000) return '${trim((n / 100000000).toStringAsFixed(1))}亿';
    if (n >= 10000) return '${trim((n / 10000).toStringAsFixed(1))}万';
    return '$n';
  }
}
