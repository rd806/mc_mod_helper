import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/model/mod_category.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';

import '../api/mcmod.dart';
import '../api/modrinth.dart';

/// 模组信息来源
enum ModSource { mcmod, modrinth, curseforge }

/// 搜索信息来源
enum FeatureSource { none, createTime, lastEditTime }

/// 管理信息来源
class SourceManager {
  /// 字符串转 ModSource
  static ModSource sourceToString(String? value) {
    return ModSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ModSource.mcmod,
    );
  }

  /// 字符串转 FeatherSource
  static FeatureSource featureToString(String? value) {
    return FeatureSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FeatureSource.none,
    );
  }

  /// 获取主页推荐，需要三个参数：
  /// - 来源，
  /// - 排序方法，
  /// - 数量限制
  ///
  /// mcmod 用列表页 sort 参数；modrinth/curseforge 各自由
  /// [ModrinthApi.getFeaturedMods] / [CurseforgeApi.getFeaturedMods]
  /// 把 [featureSource] 映射成平台自己的排序参数
  static Future<List<ModSummary>> getFeature(
    ModSource modSource,
    FeatureSource featureSource,
    int limit,
  ) async {
    switch (modSource) {
      case ModSource.mcmod:
        final sort = switch (featureSource) {
          FeatureSource.none => '',
          FeatureSource.createTime => 'createtime',
          FeatureSource.lastEditTime => 'lastedittime',
        };
        return await McmodApi.getFeaturedMods(sort: sort, limit: limit);
      case ModSource.modrinth:
        return await ModrinthApi.getFeaturedMods(
          sort: featureSource,
          limit: limit,
        );
      case ModSource.curseforge:
        return await CurseforgeApi.getFeaturedMods(
          sort: featureSource,
          limit: limit,
        );
    }
  }

  /// 获取主页分类
  static Future<List<ModCategory>> getCategory(ModSource source) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.getCategories();
      case ModSource.modrinth:
        return await ModrinthApi.getCategories();
      case ModSource.curseforge:
        return await CurseforgeApi.getCategories();
    }
  }

  /// 单一搜索
  static Future<List<ModSummary>> getSearch(
    ModSource source,
    String keyword,
  ) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.search(keyword);
      case ModSource.modrinth:
        return await ModrinthApi.search(keyword);
      case ModSource.curseforge:
        return await CurseforgeApi.search(keyword);
    }
  }

  /// 聚合搜索:并发请求各来源,单个来源失败不影响其它来源。
  ///
  /// 返回值:
  /// - [results]: 成功来源的搜索结果(空列表也正常收录)
  /// - [errors]: 失败来源的错误信息(页面按来源展示)
  ///
  /// 验证码异常([McmodCaptchaException])不在这里吞掉:直接上抛给页面
  /// 弹窗让用户手动解决,解决后整组重试(成功来源的结果有会话缓存,
  /// 重试无额外请求开销)。
  static Future<
    ({Map<ModSource, List<ModSummary>> results, Map<ModSource, String> errors})
  >
  getTotalSearch(List<ModSource> modSource, String keyword) async {
    final results = <ModSource, List<ModSummary>>{};
    final errors = <ModSource, String>{};
    // 并发发起,每个来源独立收集结果或错误
    final entries = await Future.wait(
      modSource.map((source) async {
        try {
          final mods = await getSearch(source, keyword);
          return (source: source, mods: mods, error: null);
        } on McmodCaptchaException {
          rethrow; // 验证码必须用户手动解决,上抛给页面
        } catch (e) {
          return (source: source, mods: null, error: e.toString());
        }
      }),
    );
    for (final (source: s, mods: m, error: e) in entries) {
      if (m != null) {
        results[s] = m;
      } else {
        errors[s] = e!;
      }
    }
    return (results: results, errors: errors);
  }

  /// 根据来源获取地址
  static String getUrl(ModSource source, String id) {
    switch (source) {
      case ModSource.mcmod:
        return 'https://www.mcmod.cn/class/$id.html';
      case ModSource.modrinth:
        return 'https://modrinth.com/mod/$id';
      case ModSource.curseforge:
        return 'https://www.curseforge.com/minecraft/mc-mods/$id';
    }
  }

  /// 获取来源字符串
  static String getSourceString(ModSource source) {
    switch (source) {
      case ModSource.mcmod:
        return 'MC百科';
      case ModSource.modrinth:
        return 'Modrinth';
      case ModSource.curseforge:
        return 'CurseForge';
    }
  }
}
