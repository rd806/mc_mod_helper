import 'package:flutter/material.dart';

/// 项目类型:同一批接口下的资源种类。
///
/// 枚举名与 Modrinth 的 project_type 取值一一对应
/// (mod / modpack / resourcepack / shader / plugin),
/// 解析时可以直接按名字还原;其它站点各自映射到这个集合。
enum ProjectType { mod, modpack, resourcepack, shader, plugin }

/// 管理项目类型:显示名 / 图标 / 持久化
///
/// 目前应用只收集模组,其余类型是「先备好词汇表」——
/// 收藏与浏览历史里已按类型落库,之后接入整合包等资源时,
/// 旧的模组记录不会与新记录混为一谈。
class ProjectTypeManager {
  /// 类型显示名(界面用)
  static String getTypeTitle(ProjectType type) => switch (type) {
    ProjectType.mod => '模组',
    ProjectType.modpack => '整合包',
    ProjectType.resourcepack => '材质包',
    ProjectType.shader => '光影',
    ProjectType.plugin => '插件',
  };

  /// 类型图标(列表/卡片的类型标记用)
  static Widget getTypeIcon(ProjectType type) => switch (type) {
    ProjectType.mod => const Icon(Icons.extension),
    ProjectType.modpack => const Icon(Icons.widgets),
    ProjectType.resourcepack => const Icon(Icons.palette),
    ProjectType.shader => const Icon(Icons.auto_awesome),
    ProjectType.plugin => const Icon(Icons.bolt),
  };

  /// 持久化:存枚举名而非 index(枚举增删/改序后旧数据不失效,
  /// 与 ModSource 的存法一致)
  static String typeToString(ProjectType type) => type.name;

  /// 还原持久化的类型名。
  ///
  /// 未知值或缺失(接入类型之前存下的旧记录)一律回落到 [ProjectType.mod]:
  /// 那时应用里只有模组
  static ProjectType typeFromString(String? value) {
    return ProjectType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProjectType.mod,
    );
  }
}
