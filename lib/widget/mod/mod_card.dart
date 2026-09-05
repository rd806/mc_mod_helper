import 'package:flutter/material.dart';
import 'package:mc_mod_helper/value/source.dart';

import '../../model/mod_summary.dart';
import '../../page/more/detail.dart';
import '../link_icons.dart';
import 'favorite_toggle.dart';

/// 分类页模组卡片的公共基类:
/// 卡片外壳(涟漪+跳转详情页)、标题拆分、标题/描述/来源构建等公共逻辑放这里,
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
                source: mod.source,
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
  Widget buildInfoContent(ThemeData theme) {
    final name = extractAB(mod.displayName);
    // 次要名称优先用解析得到的 subName(mcmod 列表页单独提供,
    // 标题里没有括号),否则从标题括号里拆;两者都没有时只显示主标题
    final sub = mod.subName ?? (name[0] != name[1] ? name[1] : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildTitle(theme, name[0], sub),
        buildDescription(theme),
        const SizedBox(height: 6),
        buildSource(theme),
      ],
    );
  }

  // 构建标题(主标题+可选副标题)
  Widget buildTitle(ThemeData theme, String main, String? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题
        Text(
          main,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        // 副标题
        if (sub != null) ...[
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget buildDescription(ThemeData theme) {
    final description = mod.description;
    if (description.isEmpty) return const SizedBox.shrink();

    return Text(
      mod.description,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget buildSource(ThemeData theme) {
    return Chip(
      avatar: LinkIcons.getIconForDataSource(mod.source),
      backgroundColor: Colors.transparent,
      label: Text(
        SourceManager.getSourceString(mod.source),
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}

/// 分类页的模组行卡片（窄屏）:左侧封面缩略图,右侧标题、描述与来源
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
            // 收藏心形:与 ModTile 行为一致,点击收藏/取消收藏
            FavoriteToggle(mod: mod),
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
              width: 100,
              height: 80,
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

/// 分类页的模组列卡片（宽屏网格）:上方大封面,下方标题、描述与来源
class ModCardColumn extends ModCard {
  const ModCardColumn({super.key, required super.mod});

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
                child: buildInfoContent(theme),
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
              child: FavoriteToggle(mod: mod),
            ),
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
