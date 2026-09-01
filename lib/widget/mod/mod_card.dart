import 'package:flutter/material.dart';

import '../../model/mod.dart';
import '../../page/detail.dart';

/// 分类页模组卡片的公共基类:
/// 卡片外壳(涟漪+跳转详情页)、标题拆分、标题与统计构建等公共逻辑放这里,
/// 行/列两种卡片只覆写封面([buildCover])与整体布局([build])。
abstract class ModCard extends StatelessWidget {
  const ModCard({super.key, required this.mod});

  final ModSummary mod;

  /// 提取主/副标题:displayName 里括号内的英文名作为副标题;
  /// 无括号时两者相同(只显示主标题)
  List<String> extractAB(String text) {
    var a = text;
    var b = text;
    final m = RegExp(r'(.+?)\((.+?)\)').firstMatch(text);
    if (m != null) {
      a = m.group(1)!.trim();
      b = m.group(2)!.trim();
    }
    return [a, b];
  }

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
              builder: (_) => DetailPage(
                id: mod.id,
                initialTitle: mod.displayName,
                initialDescription: mod.description,
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

  /// 信息区内容:标题 + 可选统计(两种卡片共用)
  Widget buildInfoContent(ThemeData theme) {
    final name = extractAB(mod.displayName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildTitle(theme, name),
        if (mod.statsText != null) ...[
          const SizedBox(height: 4),
          buildStatistic(theme),
        ],
      ],
    );
  }

  // 构建标题(主标题+可选副标题)
  Widget buildTitle(ThemeData theme, List<String> name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题
        Text(
          name[0],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        // 副标题
        if (name[0] != name[1]) ...[
          Text(
            name[1],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        ],
      ],
    );
  }

  // 构建统计
  Widget buildStatistic(ThemeData theme) {
    return Text(
      mod.statsText!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 分类页的模组行卡片（窄屏）:左侧封面缩略图,右侧标题与统计
class ModCardRow extends ModCard {
  const ModCardRow({super.key, required super.mod});

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
            Expanded(child: buildInfoContent(theme)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildCover(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: mod.iconUrl == null
          ? _buildThumbPlaceholder(theme)
          : Image.network(
              mod.iconUrl!,
              width: 72,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildThumbPlaceholder(theme),
            ),
    );
  }

  Widget _buildThumbPlaceholder(ThemeData theme) {
    return Container(
      width: 72,
      height: 54,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined, size: 24),
    );
  }
}

/// 分类页的模组列卡片（宽屏网格）:上方大封面,下方标题与统计
class ModCardColumn extends ModCard {
  const ModCardColumn({super.key, required super.mod});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildShell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded 吸收剩余高度,任何文本长度下都不会溢出
          buildCover(theme),
          Padding(
            padding: const EdgeInsets.all(8),
            child: buildInfoContent(theme),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildCover(ThemeData theme) {
    return Expanded(
      child: mod.iconUrl == null
          ? _buildCoverPlaceholder(theme)
          : Image.network(
              mod.iconUrl!,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildCoverPlaceholder(theme),
            ),
    );
  }

  Widget _buildCoverPlaceholder(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.image_outlined, size: 48)),
    );
  }
}
