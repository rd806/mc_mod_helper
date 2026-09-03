import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/model/mod_category.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';

import 'mcmod.dart';
import 'modrinth.dart';

/// 模组信息来源
enum ModSource { mcmod, modrinth, curseforge }

class SourceManager {
  /// 字符串转 ModSource
  static ModSource fromString(String? value) {
    return ModSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ModSource.mcmod,
    );
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
