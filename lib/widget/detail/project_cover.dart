import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

import '../../icon/icon_manager.dart';
import '../../model/project/project_detail.dart';
import '../common/image_box.dart';

/// 详情页封面与标题的公共基类:
/// 点击封面开灯箱、名称+副标题构建等公共逻辑,
/// 窄屏(竖排)与宽屏(横排)两种布局各自覆写 [build]。
abstract class ModCover extends StatelessWidget {
  const ModCover({super.key, required this.project});

  final ProjectDetail project;

  /// 打开灯箱
  void _showLightbox(BuildContext context, String url) {
    showImageBox(context, url);
  }

  /// 封面图(无封面时显示占位块),点击打开灯箱。
  /// [width]/[height] 由子类按布局决定
  Widget _buildIcon(BuildContext context, {double? width, double? height}) {
    final theme = Theme.of(context);
    final image = project.coverUrl == null
        ? null
        : Image.network(
            project.coverUrl!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(theme, width: width, height: height),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: project.coverUrl == null
            ? null
            : () => _showLightbox(context, project.coverUrl!),
        child: image ?? _buildPlaceholder(theme, width: width, height: height),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme, {double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_not_supported, size: 48),
    );
  }

  /// 名称 + 副标题 + 信息(非滚动 Column;ListView 在 Column/Row 里
  /// 会因无限高约束而崩溃)
  Widget _buildName(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Text(
          project.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        // 副标题
        if (project.subName != null) ...[
          Text(
            project.subName!,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        _buildDescription(theme),
        _buildStatistic(theme),
      ],
    );
  }

  // 显示来源
  Widget _buildSource(ThemeData theme) {
    return Chip(
      avatar: IconManager.getIconForDataSource(project.source),
      backgroundColor: Colors.transparent,
      label: Text(
        SourceManager.getSourceString(project.source),
        style: theme.textTheme.labelMedium,
      ),
    );
  }

  // 显示类别
  Widget _buildType(ThemeData theme) {
    return Chip(
      avatar: ProjectTypeManager.getTypeIcon(project.type),
      label: Text(
        ProjectTypeManager.getTypeTitle(project.type),
        style: theme.textTheme.labelMedium,
      ),
    );
  }

  // 显示描述
  Widget _buildDescription(ThemeData theme) {
    final description = project.description;
    if (description == null || description.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      description,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  // 统计信息
  Widget _buildStatistic(ThemeData theme) {
    final statistic = project.statistics;
    List<Widget> widget = [];

    if (statistic == null || statistic.isEmpty) return const SizedBox.shrink();

    for (final entry in statistic) {
      widget.add(IconManager.buildStatisticLabel(entry, theme));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 10,
        children: [_buildSource(theme), _buildType(theme), ...widget],
      ),
    );
  }
}

/// 窄屏格式:封面在上,标题在下
class ModCoverNarrow extends ModCover {
  const ModCoverNarrow({super.key, required super.project});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        _buildIcon(context, width: double.infinity, height: 200),
        _buildName(context),
        const Divider(),
      ],
    );
  }
}

/// 宽屏格式:封面缩略图在左,标题在右
class ModCoverWide extends ModCover {
  const ModCoverWide({super.key, required super.project});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(context, width: 240, height: 180),
            const SizedBox(width: 16),
            Expanded(child: _buildName(context)),
          ],
        ),
        const Divider(),
      ],
    );
  }
}
