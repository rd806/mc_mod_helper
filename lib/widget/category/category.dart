import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';

import '../../model/mod_category.dart';
import '../../page/more/category.dart';

/// MC百科的分类 id(数字字符串) → 图标(实时抓取的分类中未知的 id 用兜底图标)
const Map<String, IconData> _categoryIcons = {
  '1': Icons.memory, // 科技
  '2': Icons.auto_awesome, // 魔法
  '3': Icons.explore, // 冒险
  '4': Icons.agriculture, // 农业
  '5': Icons.palette, // 装饰
  '7': Icons.api, // LIB
  '21': Icons.tune, // 魔改
  '23': Icons.build, // 实用
  '24': Icons.support_agent, // 辅助
};

/// Modrinth 分类名 → 图标(未收录的用兜底图标)
const Map<String, IconData> _modrinthCategoryIcons = {
  'adventure': Icons.explore,
  'cursed': Icons.auto_fix_high,
  'decoration': Icons.palette,
  'economy': Icons.monetization_on,
  'equipment': Icons.shield_outlined,
  'food': Icons.restaurant,
  'game-mechanics': Icons.extension,
  'library': Icons.api,
  'magic': Icons.auto_awesome,
  'management': Icons.business_center,
  'minigame': Icons.sports_esports,
  'mobs': Icons.pets,
  'optimization': Icons.speed,
  'social': Icons.forum,
  'storage': Icons.inventory_2,
  'technology': Icons.memory,
  'transportation': Icons.train,
  'utility': Icons.build,
  'worldgen': Icons.public,
};

/// CurseForge 分类中文名 → 图标(与 CurseforgeApi._categoryNames 一致,
/// 未收录的用兜底图标;CF 分类 id 是数字,不能像 slug 那样作键)
const Map<String, IconData> _curseforgeCategoryIcons = {
  '冒险与RPG': Icons.explore,
  '装备': Icons.shield_outlined,
  '装饰': Icons.palette,
  '维度': Icons.public,
  '能量与物流': Icons.swap_horiz,
  '农业': Icons.agriculture,
  '食物': Icons.restaurant,
  '工业': Icons.factory,
  '魔法': Icons.auto_awesome,
  '生物': Icons.pets,
  '交通': Icons.train,
  '红石': Icons.bolt,
  '服务端实用': Icons.dns,
  '存储': Icons.inventory_2,
  '科技': Icons.memory,
  '实用': Icons.build,
  '世界生成': Icons.public,
  '地图与信息': Icons.map,
  '前置库': Icons.api,
  '教育': Icons.school,
  '杂项': Icons.category,
  'Fabric': Icons.extension,
  'Forge': Icons.extension,
  'NeoForge': Icons.extension,
  'Quilt': Icons.extension,
};

/// 分类行：每个分类占为一个居中的 ListTile，点击进入分类模组列表
class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.category});

  final ModCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: ListTile(
          leading: Icon(
            _categoryIcon(category),
            size: 30,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: category.slogan == null
              ? null
              : Text(
                  category.slogan!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CategoryPage(category: category)),
          ),
        ),
      ),
    );
  }

  /// 分类图标:按数据来源选择映射表
  IconData _categoryIcon(ModCategory category) {
    switch (category.source) {
      case ModSource.mcmod:
        return _categoryIcons[category.id] ?? Icons.category;
      case ModSource.modrinth:
        return _modrinthCategoryIcons[category.id] ?? Icons.category;
      case ModSource.curseforge:
        return _curseforgeCategoryIcons[category.name] ?? Icons.category;
    }
  }
}
