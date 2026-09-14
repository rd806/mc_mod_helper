import 'package:flutter/material.dart';

import '../service/value/display.dart';
import '../service/value/source.dart';
import 'link_icons.dart';

/// 管理图标
/// 包括“相关链接”、设置界面等的图标
class IconManager {
  /// 获取链接图标
  static Widget getLinkIcon(String name) {
    final n = name.toLowerCase();
    if (n == 'forge') return Icon(LinkIcons.forge, color: Colors.blue);
    if (n == 'fabric') return Icon(LinkIcons.fabric, color: Colors.green);
    if (n == 'neoforge') return Icon(LinkIcons.neoforge, color: Colors.orange);
    if (n == 'quilt') return Icon(LinkIcons.quilt, color: Colors.blueAccent);

    if (n.contains('github')) {
      return Icon(LinkIcons.github, color: Colors.black);
    }
    if (n.contains('gitlab')) return Icon(LinkIcons.gitlab, color: Colors.red);
    if (n.contains('gitee') || n.contains('码云')) {
      return Icon(LinkIcons.gitee, color: Colors.red);
    }

    if (n.contains('curseforge')) {
      return Icon(LinkIcons.curseforge, color: Colors.orange);
    }
    if (n.contains('modrinth')) {
      return Icon(LinkIcons.modrinth, color: Colors.green);
    }

    if (n.contains('wiki')) return Icon(LinkIcons.wiki);
    if (n.contains('discord')) return Icon(LinkIcons.discord);
    if (n.contains('patreon')) return Icon(LinkIcons.patreon);
    if (n.contains('mc') || n.contains('minecraft')) return Icon(LinkIcons.mc);
    if (n.contains('crowdin')) {
      return Icon(LinkIcons.crowdin, color: Colors.green);
    }

    if (n.contains('youtube')) return Icon(LinkIcons.youtube);
    if (n.contains('b站')) return Icon(LinkIcons.bilibili, color: Colors.pink);

    if (n.contains('qq')) return Icon(LinkIcons.qq, color: Colors.blue);
    if (n.contains('网盘') || n.contains('云盘') || n.contains('蓝奏云')) {
      return Icon(Icons.cloud);
    }
    if (n.contains('maven')) return Icon(Icons.code_rounded);
    return Icon(Icons.link);
  }

  /// 获取主题图标
  static Widget getIconForThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icon(Icons.settings_suggest);
      case ThemeMode.light:
        return Icon(Icons.light_mode);
      case ThemeMode.dark:
        return Icon(Icons.dark_mode);
    }
  }

  /// 获取展示方式图标
  static Widget getIconForDisplayStyle(DisplayStyle style) {
    switch (style) {
      case DisplayStyle.card:
        return Icon(Icons.view_module_rounded);
      case DisplayStyle.table:
        return Icon(Icons.table_rows_rounded);
      case DisplayStyle.auto:
        return Icon(Icons.hdr_auto_rounded);
    }
  }

  /// 获取数据来源图标
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

  /// 根据统计信息选择合适 Chips
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
