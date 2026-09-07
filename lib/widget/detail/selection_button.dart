import 'package:flutter/material.dart';

/// 窄屏模式下的选择界面
class SelectionButton extends StatelessWidget {
  const SelectionButton({
    super.key,
    required this.button,
    required this.selectedIndex,
    required this.switchTo,
  });

  final List<(String, int)> button;
  final int selectedIndex;
  final void Function(int index) switchTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _buildButton(theme),
        ),
      ),
    );
  }

  List<Widget> _buildButton(ThemeData theme) {
    List<Widget> buttons = [];

    for (final entry in button) {
      buttons.add(
        TextButton(
          style: TextButton.styleFrom(
            backgroundColor: (selectedIndex == entry.$2)
                ? theme.colorScheme.onPrimary
                : Colors.transparent,
          ),
          onPressed: () => switchTo(entry.$2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              entry.$1,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: (selectedIndex == entry.$2)
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return buttons;
  }
}
