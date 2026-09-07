import 'package:flutter/material.dart';

import '../../model/mod/mod_detail.dart';
import '../common/collapsible_widgets.dart';
import '../common/label.dart';
import 'section_title.dart';

/// 支持版本:按加载器分组展示,每组一个加载器标签 + 折叠 chips
class ModVersionCard extends StatelessWidget {
  const ModVersionCard({super.key, required this.mod});

  final ModDetail mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versions = mod.mcVersions;
    if (versions.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DetailSectionTitle(
              title: '支持版本',
              icon: Icons.check_circle_rounded,
            ),
            for (final entry in mod.mcVersions.entries)
              if (entry.value.isNotEmpty) ...[
                Text(
                  entry.key,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                CollapsibleWidgets(
                  widget: [
                    for (final v in entry.value)
                      Label(text: Text(v, style: theme.textTheme.labelMedium)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}
