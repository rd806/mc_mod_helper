import 'package:flutter/material.dart';

import '../../service/value/source.dart';

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
  // 模组类
  static const IconData forge = IconData(0xf001, fontFamily: linkFont);
  static const IconData fabric = IconData(0xf002, fontFamily: linkFont);
  static const IconData neoforge = IconData(0xf003, fontFamily: linkFont);
  static const IconData quilt = IconData(0xf004, fontFamily: linkFont);
  // 发布站类
  static const IconData github = IconData(0xe906, fontFamily: linkFont);
  static const IconData gitee = IconData(0xf908, fontFamily: linkFont);
  static const IconData gitlab = IconData(0xf4c1, fontFamily: linkFont);
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
  static Widget getLinkIcon(String name) {
    final n = name.toLowerCase();
    if (n == 'forge') return Icon(forge, color: Colors.blue);
    if (n == 'fabric') return Icon(fabric, color: Colors.green);
    if (n == 'neoforge') return Icon(neoforge, color: Colors.orange);
    if (n == 'quilt') return Icon(quilt, color: Colors.blueAccent);

    if (n.contains('github')) return Icon(github, color: Colors.black);
    if (n.contains('gitlab')) return Icon(gitlab, color: Colors.red);
    if (n.contains('gitee') || n.contains('码云')) {
      return Icon(gitee, color: Colors.red);
    }

    if (n.contains('curseforge')) return Icon(curseforge, color: Colors.black);
    if (n.contains('modrinth')) return Icon(modrinth, color: Colors.green);

    if (n.contains('wiki')) return Icon(wiki);
    if (n.contains('discord')) return Icon(discord);
    if (n.contains('patreon')) return Icon(patreon);
    if (n.contains('mc') || n.contains('minecraft')) return Icon(mc);
    if (n.contains('crowdin')) return Icon(crowdin, color: Colors.green);

    if (n.contains('youtube')) return Icon(youtube);
    if (n.contains('b站')) return Icon(bilibili, color: Colors.pink);

    if (n.contains('qq')) return Icon(qq, color: Colors.blue);
    if (n.contains('网盘') || n.contains('云盘') || n.contains('蓝奏云')) {
      return Icon(Icons.cloud);
    }
    if (n.contains('maven')) return Icon(Icons.code_rounded);
    return Icon(Icons.link);
  }

  // 获取图标
  static Widget getIconForDataSource(ModSource source) {
    switch (source) {
      case ModSource.mcmod:
        return Icon(LinkIcons.mc);
      case ModSource.modrinth:
        return Icon(LinkIcons.modrinth, color: Colors.green);
      case ModSource.curseforge:
        return Icon(LinkIcons.curseforge, color: Colors.grey);
    }
  }

  // 根据统计信息选择合适 Chips
  static Widget buildStatisticLabel((String, String) entry, ThemeData theme) {
    IconData icon = Icons.info_outline;
    String label = '${entry.$1}：${entry.$2}';
    switch (entry.$1) {
      case 'downloads':
        icon = Icons.download;
        label = '下载：${entry.$2}';
        break;
      case 'favorite':
      case 'followers':
        icon = Icons.favorite_rounded;
        label = '关注：${entry.$2}';
        break;
      case 'recommend':
        icon = Icons.thumb_up_rounded;
        label = '推荐：${entry.$2}';
        break;
      case 'views':
        icon = Icons.visibility;
        label = '总浏览：${entry.$2}';
        break;
      case 'index':
        icon = Icons.trending_up;
        label = '昨日指数：${entry.$2}';
        break;
      case 'fillRate':
        icon = Icons.percent;
        label = '资料填充率：${entry.$2}';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}
