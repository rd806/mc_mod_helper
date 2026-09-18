import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_summary.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';

import '../../api/mcmod.dart';
import '../../api/modrinth.dart';

/// 模组信息来源
enum ModSource { mcmod, modrinth, curseforge }

/// 管理信息来源
class SourceManager {
  /// 字符串转 ModSource
  static ModSource sourceToString(String? value) {
    return ModSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ModSource.mcmod,
    );
  }

  /// 组合筛选分页查询:按 [filter] 的资料来源分发,返回该页模组与总页数,
  /// 由浏览页滚到底时增量请求。
  ///
  /// 各来源自己把 [Filter] 翻译成平台的参数(分类/版本/排序的拼法互不相同,
  /// 能否组合由各站点决定);浏览页只负责「显示的就是筛选栏里选的」。
  static Future<({List<ProjectSummary> mods, int totalPages})> getFilteredMods(
    Filter filter, {
    int page = 1,
  }) async {
    switch (filter.modSource) {
      case ModSource.mcmod:
        return await McmodApi.getFilteredMods(filter, page: page);
      case ModSource.modrinth:
        return await ModrinthApi.getFilteredMods(filter, page: page);
      case ModSource.curseforge:
        return await CurseforgeApi.getFilteredMods(filter, page: page);
    }
  }

  /// 获取主页分类
  static Future<List<ProjectCategory>> getCategory(ModSource source) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.getCategories();
      case ModSource.modrinth:
        return await ModrinthApi.getCategories();
      case ModSource.curseforge:
        return await CurseforgeApi.getCategories();
    }
  }

  /// 获取游戏版本列表(浏览页筛选栏的版本选项)
  static Future<List<ProjectVersion>> getVersions(ModSource source) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.getVersions();
      case ModSource.modrinth:
        return await ModrinthApi.getVersions();
      case ModSource.curseforge:
        return await CurseforgeApi.getVersions();
    }
  }

  /// 单一搜索
  static Future<List<ProjectSummary>> getSearch(
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
    ({
      Map<ModSource, List<ProjectSummary>> results,
      Map<ModSource, String> errors,
    })
  >
  getTotalSearch(List<ModSource> modSource, String keyword) async {
    final results = <ModSource, List<ProjectSummary>>{};
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
