import 'package:mc_mod_helper/page/detail.dart';

import '../model/mod_detail.dart';
import 'mcmod.dart';
import 'modrinth.dart';

/// 模组信息来源
enum ModSource {
  mcmod,
  modrinth
}

class SourceManager {
  /// 根据来源获取地址
  static String getUrl(ModSource source, String id) {
    switch (source) {
      case ModSource.mcmod: return 'https://www.mcmod.cn/class/$id.html';
      case ModSource.modrinth: return 'https://modrinth.com/mod/$id';
    }
  }

  /// 获取来源字符串
  static String getSourceString(ModSource source) {
    switch (source) {
      case ModSource.mcmod: return 'MC百科';
      case ModSource.modrinth: return 'Modrinth';
    }
  }

  /// 获取详细信息
  static Future<ModDetail> getModDetail(ModSource source, DetailPage widget) {
    switch (source) {
      case ModSource.mcmod:
        return McmodApi.getDetail(
          widget.id,
          fallbackDescription: widget.initialDescription,
        );
      case ModSource.modrinth:
        return ModrinthApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription
        );
    }
  }
}


