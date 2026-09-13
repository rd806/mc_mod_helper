import 'package:flutter/material.dart';

/// 详情页区块标题:图标 + titleLarge 加粗标题,配合 ... 展开使用。
///
/// 允许后接一些组件，例如翻译、更多等。
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.icon,
    this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // 上下间距写入 Padding 中
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (children != null) ...[for (final child in children!) child],
        ],
      ),
    );
  }
}
