import 'package:flutter/material.dart';

import '../../model/mod_category.dart';
import '../../page/category.dart';

/// MC百科的分类 id(数字字符串) → 图标(实时抓取的分类中未知的 id 用兜底图标)
const Map<String, IconData> _categoryIcons = {
  '1': Icons.memory,          // 科技
  '2': Icons.auto_awesome,    // 魔法
  '3': Icons.explore,         // 冒险
  '4': Icons.agriculture,     // 农业
  '5': Icons.palette,         // 装饰
  '7': Icons.api,             // LIB
  '21': Icons.tune,           // 魔改
  '23': Icons.build,          // 实用
  '24': Icons.support_agent,  // 辅助
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
          subtitle: category.slogan == null ? null : Text(
            category.slogan!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CategoryPage(category: category)),
          ),
        ),
      )
    );
  }

  /// 分类图标:按数据来源选择映射表
  IconData _categoryIcon(ModCategory category) {
    if (category.source == 'modrinth') {
      return _modrinthCategoryIcons[category.id] ?? Icons.category;
    }
    return _categoryIcons[category.id] ?? Icons.category;
  }
}