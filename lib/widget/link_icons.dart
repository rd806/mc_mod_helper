import 'package:flutter/material.dart';

import '../api/source.dart';

/// 链接图标(自定义图标字体)。
///
/// 字体文件 assets/icon/link_icons.ttf 由 IcoMoon/FlutterIcon 等工具生成,
/// 其内部 family 名必须与 pubspec.yaml 中声明的 LinkIcons 一致。
///
/// 每个图标的 codePoint 以生成工具输出的为准(见样式表里的 content: "\e900"
/// 之类,去掉反斜杠就是 0xe900)。
class LinkIcons {
  LinkIcons._();

  /// 与 pubspec.yaml 中声明的字体 family 对应
  static const String linkFont = 'LinkIcons';

  /// 拿到生成的字体文件后，按工具输出的 codePoint 修正以下值
  // 发布站类
  static const IconData github = IconData(0xe906, fontFamily: linkFont);
  static const IconData curseforge = IconData(0xf09d, fontFamily: linkFont);
  static const IconData modrinth = IconData(0xf1a8, fontFamily: linkFont);
  // 论坛类
  static const IconData wiki = IconData(0xe904, fontFamily: linkFont);
  static const IconData discord = IconData(0xe903, fontFamily: linkFont);
  static const IconData patreon = IconData(0xe905, fontFamily: linkFont);
  static const IconData mc = IconData(0xf164, fontFamily: linkFont);
  static const IconData crowdin = IconData(0xf2c5, fontFamily: linkFont);
  // 视频站类
  static const IconData bilibili = IconData(0xf000, fontFamily: linkFont);
  static const IconData youtube = IconData(0xe901, fontFamily: linkFont);
  static const IconData qq = IconData(0xfd02, fontFamily: linkFont);

  /// 获取链接图标
  static IconData getLinkIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('github')) return github;
    if (n.contains('curse') || n.contains('forge')) return curseforge;
    if (n.contains('modrinth')) return modrinth;

    if (n.contains('wiki')) return wiki;
    if (n.contains('discord')) return discord;
    if (n.contains('patreon')) return patreon;
    if (n.contains('mc') || n.contains('minecraft')) return mc;
    if (n.contains('crowdin')) return crowdin;

    if (n.contains('youtube')) return youtube;
    if (n.contains('b站')) return bilibili;

    if (n.contains('qq')) return qq;
    if (n.contains('网盘')) return Icons.cloud;
    if (n.contains('maven')) return Icons.code_rounded;
    return Icons.link;
  }

  // 获取图标
  static IconData getIconForDataSource(ModSource source) {
    switch (source) {
      case ModSource.mcmod:
        return LinkIcons.mc;
      case ModSource.modrinth:
        return LinkIcons.modrinth;
      case ModSource.curseforge:
        return LinkIcons.curseforge;
    }
  }
}
