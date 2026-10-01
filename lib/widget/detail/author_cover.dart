import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/author/author_detail.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

import '../../icon/icon_manager.dart';
import '../common/image_box.dart';

/// 作者页头部:头像 + 名称 + 来源 + 简介。
///
/// 作者页只有这一份内容,不做窄/宽两套布局(与详情页的封面不同):
/// 头像固定尺寸,右侧信息自适应,左右留白由页面按宽度给。
class AuthorCover extends StatelessWidget {
  const AuthorCover({
    super.key,
    required this.author,
    this.fallbackName,
    this.fallbackAvatarUrl,
  });

  /// 作者主页数据
  final AuthorDetail author;

  /// 名字回退:CurseForge 的作者接口拿不到名字,用卡片带过来的
  final String? fallbackName;

  /// 头像回退:同上
  final String? fallbackAvatarUrl;

  String? get _name => author.name ?? fallbackName;

  String? get _avatarUrl => author.avatarUrl ?? fallbackAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(context),
            const SizedBox(width: 16),
            Expanded(child: _buildInfo(theme)),
          ],
        ),
        const Divider(),
      ],
    );
  }

  /// 头像(没有头像时用占位图标),点击开灯箱
  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final url = _avatarUrl;
    const size = 120.0;
    final image = url == null || url.isEmpty
        ? null
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(theme, size),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: image == null ? null : () => showImageBox(context, url!),
        child: image ?? _buildPlaceholder(theme, size),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.person, size: 48),
    );
  }

  /// 名称 + 来源胶囊 + 简介
  Widget _buildInfo(ThemeData theme) {
    final name = _name;
    final bio = author.bio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Text(
          name == null || name.isEmpty ? '未知作者' : name,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Chip(
          avatar: IconManager.getIconForDataSource(author.source),
          backgroundColor: Colors.transparent,
          label: Text(
            SourceManager.getSourceString(author.source),
            style: theme.textTheme.labelMedium,
          ),
        ),
        if (bio != null && bio.isNotEmpty)
          Text(
            bio,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
