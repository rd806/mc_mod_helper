import 'package:flutter/material.dart';

import '../icon/link_icons.dart';
import 'mod/mod_loader.dart';

/// 链接名关键词 → 图标。
///
/// **书写顺序即优先级**:匹配是「名称里包含关键词」且取第一个命中的,
/// 所以更具体的词要排在前面(如 wiki 在 mc 之前:'Minecraft Wiki' 取 wiki)。
const Map<String, Widget> linkIcon = {
  'github': Icon(LinkIcons.github, color: Colors.black),
  'gitlab': Icon(LinkIcons.gitlab, color: Colors.red),
  'gitee': Icon(LinkIcons.gitee, color: Colors.red),
  '码云': Icon(LinkIcons.gitee, color: Colors.red),
  'maven': Icon(Icons.code_rounded),

  'curseforge': Icon(LinkIcons.curseforge, color: Colors.orange),
  'modrinth': Icon(LinkIcons.modrinth, color: Colors.green),

  'wiki': Icon(LinkIcons.wiki),
  'discord': Icon(LinkIcons.discord),
  'patreon': Icon(LinkIcons.patreon),
  'mc': Icon(LinkIcons.mc),
  'minecraft': Icon(LinkIcons.mc),
  'crowdin': Icon(LinkIcons.crowdin, color: Colors.green),
  'youtube': Icon(LinkIcons.youtube),
  'b站': Icon(LinkIcons.bilibili, color: Colors.pink),
  'qq': Icon(LinkIcons.qq, color: Colors.blue),

  '网盘': Icon(Icons.cloud),
  '云盘': Icon(Icons.cloud),
  '蓝奏云': Icon(Icons.cloud),
};

/// 模组外链
class Link {
  const Link({required this.icon, required this.name, required this.url});

  /// 链接图标
  final Widget icon;

  /// 链接名称
  final String name;

  /// 链接url
  final String url;

  /// 按名称取图标。
  ///
  /// 站点的链接名常常带后缀('GitHub 仓库'、'CurseForge 页面'),所以是
  /// **包含**匹配而非全等;大小写不敏感([linkIcon] 的键都写小写)。
  /// 加载器名(Forge/Fabric…)先按全等认一次:它们是另一个注册表,
  /// 且不能参与包含匹配 —— 否则 'CurseForge' 会被 'forge' 抢先命中。
  static Widget getIcon(String name) {
    final n = name.trim().toLowerCase();
    final loader = modLoaders[n];
    if (loader != null) return loader.icon;
    for (final entry in linkIcon.entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return const Icon(Icons.link);
  }
}
