import 'package:flutter/material.dart';

/// 简单的文字标签
class Label extends StatelessWidget {
  const Label({super.key, required this.text, this.icon});

  final Widget? icon;

  final Widget text;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.onSecondary, width: 0.5),
      ),
      child: Row(
        // 收缩到子组件的大小
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 5)],
          text,
        ],
      ),
    );
  }
}
