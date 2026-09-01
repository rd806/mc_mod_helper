import 'package:flutter/material.dart';

import '../../model/mod_summary.dart';
import '../../page/detail.dart';

/// 单条模组
/// 搜索结果 / 首页推荐通用
/// 图标 + 标题 + 简介 + 点击进入详情页
class ModTile extends StatelessWidget {
  const ModTile({super.key, required this.mod});

  final ModSummary mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: _buildAvatar(theme),
        title: Text(
          mod.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: mod.description.isEmpty
            ? null
            : Text(
                mod.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
        trailing: const Icon(Icons.chevron_right),
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
      ),
    );
  }

  /// 有图标就显示图标,加载失败或无图标时回退到首字母头像
  Widget _buildAvatar(ThemeData theme) {
    if (mod.iconUrl != null) {
      return ClipOval(
        child: Image.network(
          mod.iconUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _LetterAvatar(theme: theme, mod: mod),
        ),
      );
    }
    return _LetterAvatar(theme: theme, mod: mod);
  }
}

/// 首字母头像
class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({required this.theme, required this.mod});

  final ThemeData theme;
  final ModSummary mod;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        (mod.abbr ?? mod.displayName).characters.first.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
