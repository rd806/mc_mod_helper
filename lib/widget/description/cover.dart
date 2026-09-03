import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/source.dart';

import '../../model/mod_detail.dart';
import 'image_box.dart';

/// 详情页封面与标题的公共基类:
/// 点击封面开灯箱、名称+副标题构建等公共逻辑,
/// 窄屏(竖排)与宽屏(横排)两种布局各自覆写 [build]。
abstract class ModCover extends StatelessWidget {
  const ModCover({super.key, required this.mod});

  final ModDetail mod;

  /// 打开灯箱
  void _showLightbox(BuildContext context, String url) {
    showImageBox(context, url);
  }

  /// 封面图(无封面时显示占位块),点击打开灯箱。
  /// [width]/[height] 由子类按布局决定
  Widget _buildIcon(BuildContext context, {double? width, double? height}) {
    final theme = Theme.of(context);
    final image = mod.coverUrl == null
        ? null
        : Image.network(
            mod.coverUrl!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholder(theme, width: width, height: height),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: mod.coverUrl == null
            ? null
            : () => _showLightbox(context, mod.coverUrl!),
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

  /// 名称 + 副标题(非滚动 Column;ListView 在 Column/Row 里
  /// 会因无限高约束而崩溃)
  Widget _buildName(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mod.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        // 副标题
        if (mod.subName != null) ...[
          const SizedBox(height: 4),
          Text(
            mod.subName!,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        // 来源(始终有值,显示友好名称)
        const SizedBox(height: 10),
        _buildSource(context, mod),
        // 支持平台
        if (mod.platform != null || mod.environment != null) ...[
          const SizedBox(height: 16),
          _buildPlatforms(mod),
        ],
      ],
    );
  }

  // 显示来源
  Widget _buildSource(BuildContext context, ModDetail mod) {
    final theme = Theme.of(context);
    String source = SourceManager.getSourceString(mod.source);
    return Text(
      source,
      style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
    );
  }

  // 支持平台
  Widget _buildPlatforms(ModDetail mod) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (mod.platform != null) _InfoChip(label: '平台: ${mod.platform}'),
      ],
    );
  }
}

/// 窄屏格式:封面在上,标题在下
class ModCoverNarrow extends ModCover {
  const ModCoverNarrow({super.key, required super.mod});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIcon(context, width: double.infinity, height: 200),
        const SizedBox(height: 12),
        _buildName(context),
      ],
    );
  }
}

/// 宽屏格式:封面缩略图在左,标题在右
class ModCoverWide extends ModCover {
  const ModCoverWide({super.key, required super.mod});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIcon(context, width: 288, height: 180),
        const SizedBox(width: 16),
        Expanded(child: _buildName(context)),
      ],
    );
  }
}

/// 紧凑的小标签
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
