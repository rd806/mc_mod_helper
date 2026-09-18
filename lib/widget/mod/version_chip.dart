import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/page/browse.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

import '../../model/filter/sort_method.dart';

/// 版本胶囊:点击进入「按该版本筛选」的浏览页。
///
/// 用于模组详情页的「支持版本」卡片:那里点某个版本,期望看到支持它的模组。
/// 浏览页按 [Filter.modSource] 拉数据,而来源由设置(DisplaySettings)决定,
/// 两者不一致时会同时存在两个事实(页面按 A 站筛、筛选栏却显示 B 站),
/// 因此不一致时直接禁用 —— 详情页是从当前来源的列表点进来的,正常总是一致。
class VersionChip extends StatelessWidget {
  const VersionChip({super.key, required this.version});

  final ProjectVersion version;

  @override
  Widget build(BuildContext context) {
    final canOpen = version.source == DisplaySettings.instance.dataSource;
    return ActionChip(
      label: Text(version.version),
      onPressed: canOpen
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BrowsePage(
                  initialFilter: Filter(
                    modSource: version.source,
                    sortMethod: SortMethod.none,
                    version: version,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
