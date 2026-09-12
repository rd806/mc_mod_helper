import 'package:flutter/material.dart';

import '../../../model/mod/mod_detail.dart';
import '../../common/collapsible_widgets.dart';
import '../../../icon/link_icons.dart';
import '../intro/section_title.dart';

/// 相关链接(超出可展开的行数时折叠)
class LinksCard extends StatelessWidget {
  const LinksCard({super.key, required this.mod, required this.onOpenUrl});

  final ModDetail mod;

  /// 链接点击回调(灯箱/浏览器/应用内跳转由调用方分流)
  final void Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = mod.links;
    if (links.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DetailSectionTitle(
              title: '相关链接',
              icon: Icons.insert_link_rounded,
            ),
            CollapsibleWidgets(
              widget: [
                for (final link in mod.links)
                  ActionChip(
                    avatar: LinkIcons.getLinkIcon(link.name),
                    backgroundColor: theme.colorScheme.onPrimary.withAlpha(100),
                    label: Text(link.name, style: theme.textTheme.labelMedium),
                    onPressed: () => onOpenUrl(link.url),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
