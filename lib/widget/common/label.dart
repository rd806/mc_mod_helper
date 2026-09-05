import 'package:flutter/material.dart';

/// 简单的文字标签
class Label extends StatelessWidget {
  const Label({super.key, required this.entry, this.icon});

  final Widget? icon;

  final String entry;

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
        children: [
          ?icon,
          const SizedBox(width: 5),
          Text(entry, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
