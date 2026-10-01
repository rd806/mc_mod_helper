import 'package:flutter/material.dart';

/// 模组作者
class AuthorSummary {
  const AuthorSummary({
    required this.name,
    this.id,
    this.avatarUrl,
    this.role,
    this.url,
  });

  /// 名称
  final String name;

  /// 站点用户 id:mcmod 是 `/author/{id}.html` 里的数字,Modrinth 是成员列表的
  /// `user.id`,CurseForge 是 `authors[].id`。有 id 才进得了作者页
  final String? id;

  /// 头像图片链接
  final String? avatarUrl;

  /// 角色
  final String? role;

  /// 站点给的主页地址。只有 CurseForge 用得着 —— 它的作者主页按用户名拼,
  /// 光有数字 id 拼不出来;mcmod / Modrinth 的地址按 id 拼即可
  final String? url;

  /// 作者信息卡片。
  ///
  /// [onTap] 不为空时用 ActionChip(`Chip` 本身没有点击回调):
  /// 详情页里有作者 id 的芯片据此变成进作者页的入口
  static Widget buildAuthorChip(
    AuthorSummary author,
    ThemeData theme, {
    VoidCallback? onTap,
  }) {
    final label = Column(
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
    );
    final avatar = author._buildAvatar(theme);
    if (onTap == null) return Chip(avatar: avatar, label: label);
    return ActionChip(avatar: avatar, label: label, onPressed: onTap);
  }

  /// 头像:没有头像(如 CurseForge 作者不提供头像)时用占位图标
  Widget _buildAvatar(ThemeData theme) {
    final url = avatarUrl;
    if (url == null) return _buildPlaceholder(theme, width: 80, height: 80);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        url,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(theme, width: 80, height: 80),
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
