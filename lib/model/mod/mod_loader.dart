import 'package:flutter/material.dart';

import '../../icon/link_icons.dart';

/// 已知的模组加载器:键是「小写标识」,与各站点返回的写法对应
/// (mcmod / CurseForge 给 'Forge'、Modrinth 给 'forge')。
///
/// 图标与配色只在这里定义一处,界面与链接图标都从这里取。
const Map<String, ModLoader> modLoaders = {
  'forge': ModLoader(
    icon: Icon(LinkIcons.forge, color: Colors.blue),
    name: 'Forge',
  ),
  'fabric': ModLoader(
    icon: Icon(LinkIcons.fabric, color: Colors.green),
    name: 'Fabric',
  ),
  'neoforge': ModLoader(
    icon: Icon(LinkIcons.neoforge, color: Colors.orange),
    name: 'NeoForge',
  ),
  'quilt': ModLoader(
    icon: Icon(LinkIcons.quilt, color: Colors.blueAccent),
    name: 'Quilt',
  ),
};

/// 模组加载器
class ModLoader {
  const ModLoader({required this.icon, required this.name});

  /// 站点给的名字 → 加载器。
  ///
  /// 各站点写法不统一(Modrinth 全小写、mcmod 与 CurseForge 是 Forge 这样的
  /// 名称、还可能大小写不一),所以统一按小写查表。
  /// 表里没有的名字(数据包、LiteLoader 之类)保留原名、用通用图标兜底 ——
  /// 直接丢掉的话,这些分组连同版本号就一起不显示了。
  factory ModLoader.of(String name) {
    final raw = name.trim();
    return modLoaders[raw.toLowerCase()] ??
        ModLoader(icon: const Icon(Icons.extension), name: raw);
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
  bool operator ==(Object other) => other is ModLoader && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ModLoader($name)';
}
