import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';

import '../widget/mod/mod_card.dart';

/// 模组信息展示方式
/// - 卡片式:网格,每个模组一张大卡片
/// - 列表式:单行排列(左侧封面,右侧标题与统计)
/// - 自适应式:窄屏列表、宽屏网格
enum DisplayStyle { card, table, auto }

/// 展示方式管理:字符串转换 + 按展示方式构建模组列表的 sliver。
///
/// 首页推荐 / 分类模组列表 / 收藏页共用,展示方式由
/// [DisplayManager.buildSliver] 的参数指定(设置页持久化在
/// SettingsService.displayStyle)。
class DisplayManager {
  /// 字符串转 DisplayStyle(未知值回落到默认的列表式)
  static DisplayStyle displayToString(String? value) {
    return DisplayStyle.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DisplayStyle.table,
    );
  }

  /// 按 [style] 构建模组列表的 sliver,供 CustomScrollView 使用。
  ///
  /// 由调用方包一层 SliverPadding 控制边距;
  /// 空列表时 childCount 为 0,渲染为空白
  static Widget buildSliver(DisplayStyle style, List<ModSummary> mods) {
    switch (style) {
      case DisplayStyle.card:
        return _buildModGrid(mods);
      case DisplayStyle.table:
        return _buildModList(mods);
      case DisplayStyle.auto:
        // 自适应:窄屏列表、宽屏网格
        return SliverLayoutBuilder(
          builder: (context, constraints) => constraints.crossAxisExtent < 480
              ? _buildModList(mods)
              : _buildModGrid(mods),
        );
    }
  }

  /// 列表格式:模组单行排列(左侧封面,右侧标题与统计)
  static Widget _buildModList(List<ModSummary> mods) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => ModCardRow(mod: mods[i]),
        childCount: mods.length,
      ),
    );
  }

  /// 网格格式:每列约 225px 宽的大卡片。
  ///
  /// 列数按实际可用宽度计算(不能在构建时读 MediaQuery:
  /// sliver 的宽度约束要到 SliverLayoutBuilder 里才确定)
  static Widget _buildModGrid(List<ModSummary> mods) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.crossAxisExtent / 225).floor().clamp(1, 8);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ModCardColumn(mod: mods[i]),
            childCount: mods.length,
          ),
        );
      },
    );
  }
}
