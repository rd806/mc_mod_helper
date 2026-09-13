import 'package:flutter/material.dart';

/// 开关类型的配置按钮
///
/// 需要主标题，副标题，初始值，值的切换回调
class SwitchTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;

  const SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.initialValue = false,
    this.onChanged,
  });

  @override
  State<SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<SwitchTile> {
  late bool _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: SwitchListTile(
        title: Text(widget.title, style: theme.textTheme.bodyMedium),
        subtitle: Text(
          widget.subtitle,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        value: _value,
        dense: false,
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged?.call(v);
        },
      ),
    );
  }
}
