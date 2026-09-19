import 'package:flutter/material.dart';

import '../../icon/platform_icons.dart';

/// 已知的模组加载器:键是「小写标识」,与各站点返回的写法对应
/// (mcmod / CurseForge 给 'Forge'、Modrinth 给 'forge')。
///
/// 图标与配色只在这里定义一处,界面与链接图标都从这里取。
const Map<String, ProjectLoader> projectLoaders = {
  'forge': ProjectLoader(
    icon: Icon(PlatformIcons.forge, color: Colors.blue),
    name: 'Forge',
  ),
  'fabric': ProjectLoader(
    icon: Icon(PlatformIcons.fabric, color: Colors.green),
    name: 'Fabric',
  ),
  'neoforge': ProjectLoader(
    icon: Icon(PlatformIcons.neoforge, color: Colors.orange),
    name: 'NeoForge',
  ),
  'quilt': ProjectLoader(
    icon: Icon(PlatformIcons.quilt, color: Colors.blueAccent),
    name: 'Quilt',
  ),

  'bukkit': ProjectLoader(
    icon: Icon(PlatformIcons.bukkit, color: Colors.orange),
    name: 'Bukkit',
  ),
  'spigot': ProjectLoader(
    icon: Icon(PlatformIcons.spigot, color: Colors.yellow),
    name: 'Spigot',
  ),
  'paper': ProjectLoader(
    icon: Icon(PlatformIcons.paper, color: Colors.green),
    name: 'Paper',
  ),
  'purpur': ProjectLoader(
    icon: Icon(PlatformIcons.purpur, color: Colors.purple),
    name: 'Purpur',
  ),
  'folia': ProjectLoader(
    icon: Icon(PlatformIcons.folia, color: Colors.green),
    name: 'Folia',
  ),
  'bungeecord': ProjectLoader(
    icon: Icon(PlatformIcons.bungeecord, color: Colors.orange),
    name: 'BungeeCord',
  ),
  'velocity': ProjectLoader(
    icon: Icon(PlatformIcons.velocity, color: Colors.purple),
    name: 'Velocity',
  ),
  'waterfall': ProjectLoader(
    icon: Icon(PlatformIcons.waterfall, color: Colors.purple),
    name: 'Waterfall',
  ),
};

/// 服务端平台:跑这些加载器的项目在 Modrinth 上就是「插件」。
///
/// 用途是反推类型 —— Modrinth 的 `project_type` 是旧字段,插件也被报成 'mod'
/// (实测 veinminer:`project_type=mod`、`loaders=[bukkit]`),
/// 这类项目的详情没有别的类型线索,只能从加载器认
const Set<String> serverPlatforms = {
  'bukkit',
  'spigot',
  'paper',
  'purpur',
  'folia',
  'bungeecord',
  'velocity',
  'waterfall',
};

/// 模组加载器
class ProjectLoader {
  const ProjectLoader({required this.icon, required this.name});

  /// 是否服务端平台(写法大小写不一,统一按小写比)
  static bool isServerPlatform(String name) =>
      serverPlatforms.contains(name.trim().toLowerCase());

  /// 站点给的名字 → 加载器。
  ///
  /// 各站点写法不统一(Modrinth 全小写、mcmod 与 CurseForge 是 Forge 这样的
  /// 名称、还可能大小写不一),所以统一按小写查表。
  /// 表里没有的名字(数据包、LiteLoader 之类)保留原名、用通用图标兜底 ——
  /// 直接丢掉的话,这些分组连同版本号就一起不显示了。
  factory ProjectLoader.of(String name) {
    final raw = name.trim();
    return projectLoaders[raw.toLowerCase()] ??
        ProjectLoader(icon: const Icon(Icons.extension), name: raw);
  }

  /// 图标(配色写在图标上)
  final Widget icon;

  /// 显示名
  final String name;

  /// 与图标同色:颜色定义在 [icon] 上,标题文字要跟着用
  Color? get color => switch (icon) {
    Icon(:final color) => color,
    _ => null,
  };

  /// 按名称比较:同一个加载器可能由不同写法各自构造出实例,
  /// 而它会作为 Map 的键(支持的版本按加载器分组),必须能相等
  @override
  bool operator ==(Object other) =>
      other is ProjectLoader && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ModLoader($name)';
}
