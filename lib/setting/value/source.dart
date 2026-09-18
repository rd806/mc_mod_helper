import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_summary.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
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

  /// 获取分类选项(按类型:各站点的分类是按类型分开编号的)
  static Future<List<ProjectCategory>> getCategory(
    ModSource source,
    ProjectType type,
  ) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.getCategories(type);
      case ModSource.modrinth:
        return await ModrinthApi.getCategories(type);
      case ModSource.curseforge:
        return await CurseforgeApi.getCategories(type);
    }
  }

  /// 获取游戏版本列表(浏览页筛选栏的版本选项)。
  ///
  /// 游戏版本本身与类型无关,但 mcmod 的版本选项是从列表页上抓的
  /// (模组在 modlist.html、整合包在 modpack.html),所以要按类型取
  static Future<List<ProjectVersion>> getVersions(
    ModSource source,
    ProjectType type,
  ) async {
    switch (source) {
      case ModSource.mcmod:
        return await McmodApi.getVersions(type);
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

  /// 根据来源与项目类型获取页面地址。
  ///
  /// 各站点的路径段按类型分开(mcmod 的整合包在 /modpack/,Modrinth 的
  /// 路径段就是它的 project_type),所以类型必须参与拼接 —— 否则整合包
  /// 会被拼成模组地址。
  static String getUrl(ModSource source, ProjectType type, String id) {
    switch (source) {
      case ModSource.mcmod:
        // 站点上模组是 /class/、整合包是 /modpack/;
        // 其余类型(mcmod 另有材质包/光影版块)接进来时再补各自路径
        final segment = type == ProjectType.modpack ? 'modpack' : 'class';
        return 'https://www.mcmod.cn/$segment/$id.html';
      case ModSource.modrinth:
        // 路径段与 project_type 同名:/mod/ /modpack/ /resourcepack/ …
        return 'https://modrinth.com/${type.name}/$id';
      case ModSource.curseforge:
        // CurseForge 的路径段自成一套;模组与整合包已确认,
        // 其余类型的路径段待接入时核实
        final segment = switch (type) {
          ProjectType.modpack => 'modpacks',
          ProjectType.resourcepack => 'texture-packs',
          _ => 'mc-mods',
        };
        return 'https://www.curseforge.com/minecraft/$segment/$id';
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
