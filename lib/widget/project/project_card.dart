import 'package:flutter/material.dart';

import '../../model/project/project_summary.dart';
import '../../page/detail/project_page.dart';
import 'favorite_toggle.dart';

/// 分类页模组卡片的公共基类:
/// 卡片外壳(涟漪+跳转详情页)、标题拆分、标题/描述/来源构建等公共逻辑放这里,
/// 行/列两种卡片只覆写封面([buildCover])与整体布局([build])。
abstract class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});

  final ProjectSummary project;

  /// 卡片外壳:Card + InkWell 点击跳转详情页。
  /// StatelessWidget 没有 context 属性，由子类的 build 传入
  Widget buildShell(
    BuildContext context, {
    EdgeInsetsGeometry? margin,
    required Widget child,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: margin,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProjectPage(
                id: project.id,
                source: project.source,
                type: project.type,
                initialTitle: project.displayName,
                initialDescription: project.description,
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }

  /// 封面区:子类实现(行卡片=缩略图,列卡片=大图)
  Widget buildCover(ThemeData theme);

  /// 信息区内容:标题、描述与来源(两种卡片共用)
  Widget buildInfo(ThemeData theme) {
    final name = project.title;
    // 次要名称优先用解析得到的 subName(mcmod 列表页单独提供,
    // 标题里没有括号),否则从标题括号里拆;两者都没有时只显示主标题
    final sub = project.subName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        buildTitle(theme, name, sub),
        buildDescription(theme),
        buildStatistic(theme),
      ],
    );
  }

  /// 标题
  Widget buildTitle(ThemeData theme, String main, String? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          main,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
      ],
    );
  }

  /// 描述
  Widget buildDescription(ThemeData theme) {
    final description = project.description;
    if (description.isEmpty) return const SizedBox.shrink();

    return Text(
      project.description,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// 统计信息
  Widget buildStatistic(ThemeData theme) {
    final statistic = project.statisticsText;
    if (statistic == null) return const SizedBox.shrink();

    return Text(
      project.statisticsText!,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// 分类页的模组行卡片（窄屏）：
/// 左侧封面缩略图,右侧标题、描述与来源
class ModCardRow extends ProjectCard {
  const ModCardRow({super.key, required super.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildShell(
      context,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            buildCover(theme),
            const SizedBox(width: 12),
            Expanded(child: buildInfo(theme)),
            // 收藏心形:与 ModTile 行为一致,点击收藏/取消收藏
            FavoriteToggle(mod: project),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildCover(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: project.iconUrl == null
          ? _buildThumbPlaceholder(theme)
          : Image.network(
              project.iconUrl!,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildThumbPlaceholder(theme),
            ),
    );
  }

  /// 替换图片
  Widget _buildThumbPlaceholder(ThemeData theme) {
    return Container(
      width: 80,
      height: 80,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined, size: 24),
    );
  }
}

/// 分类页的模组列卡片（宽屏网格）：
/// 上方大封面,下方标题、描述与来源
class ModCardColumn extends ProjectCard {
  const ModCardColumn({super.key, required super.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildShell(
      context,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expanded 吸收剩余高度,任何文本长度下都不会溢出
              buildCover(theme),
              Padding(
                padding: const EdgeInsets.all(8),
                child: buildInfo(theme),
              ),
            ],
          ),
          // 收藏心形悬浮在封面右上角,半透明底保证在图片上可见
          Positioned(
            top: 4,
            right: 4,
            child: CircleAvatar(
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.85,
              ),
              child: FavoriteToggle(mod: project),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildCover(ThemeData theme) {
    return Expanded(
      child: project.iconUrl == null
          ? _buildCoverPlaceholder(theme)
          : Image.network(
              project.iconUrl!,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildCoverPlaceholder(theme),
            ),
    );
  }

  /// 替换图片
  Widget _buildCoverPlaceholder(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.image_outlined, size: 48)),
    );
  }
}
