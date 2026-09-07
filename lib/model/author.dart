import 'package:flutter/material.dart';

/// 模组作者
class Author {
  const Author({required this.name, this.avatarUrl, this.role});

  /// 名称
  final String name;

  /// 头像图片链接
  final String? avatarUrl;

  /// 角色
  final String? role;

  /// 作者信息卡片
  static Widget buildAuthorChip(Author author, ThemeData theme) {
    final avatar = author.avatarUrl;
    return Chip(
      // 无头像(如 CurseForge 作者不提供头像)时用占位图标
      avatar: avatar == null
          ? _buildPlaceholder(theme, width: 80, height: 80)
          : ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.network(
                avatar,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder(theme, width: 80, height: 80),
              ),
            ),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(author.name, style: theme.textTheme.labelLarge),
          if (author.role != null) ...[
            Text(
              author.role!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 默认替换图片
  static Widget _buildPlaceholder(
    ThemeData theme, {
    double? width,
    double? height,
  }) {
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      // 容器小于图标默认尺寸时让图标等比缩放，避免内容溢出
      child: const FittedBox(fit: BoxFit.contain, child: Icon(Icons.person)),
    );
  }
}
