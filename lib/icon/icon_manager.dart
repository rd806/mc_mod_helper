import 'package:flutter/material.dart';

import '../setting/value/display.dart';
import '../setting/value/source.dart';
import 'link_icons.dart';

/// 管理图标
/// 包括设置界面等的图标
class IconManager {
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
