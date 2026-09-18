import 'package:flutter/material.dart';

import '../../model/author/author_summary.dart';
import '../../model/project/project_detail.dart';
import '../common/collapsible_widgets.dart';
import '../common/section_title.dart';

/// 模组开发团队(作者信息卡片,超出可展开的行数时折叠)
class AuthorsCard extends StatelessWidget {
  const AuthorsCard({super.key, required this.project});

  final ProjectDetail project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authors = project.authors;
    if (authors == null || authors.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: '开发团队', icon: Icons.people_rounded),
            CollapsibleWidgets(
              widget: [
                for (final author in authors)
                  AuthorSummary.buildAuthorChip(author, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
