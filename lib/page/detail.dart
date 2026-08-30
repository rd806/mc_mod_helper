import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/mod.dart';
import '../api/mcmod.dart';

/// 模组详情页
class DetailPage extends StatefulWidget {
    const DetailPage({
        super.key,
        required this.id,
        this.initialTitle,
        this.initialDescription,
    });

    final int id;

    /// 详情加载完成前显示在标题栏的名称
    final String? initialTitle;

    /// 详情页没有“概述”时回退显示的简介(来自搜索结果)
    final String? initialDescription;

    @override
    State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
    late Future<ModDetail> _future;

    @override
    void initState() {
        super.initState();
        _future = _load();
    }

    /// 获取详情
    Future<ModDetail> _load() {
        return McmodApi.getDetail(
            widget.id,
            fallbackDescription: widget.initialDescription,
        );
    }

    void _reload() {
        setState(() {
            _future = _load();
        });
    }

    Future<void> _openUrl(String url) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')),);
            }
        }
    }

    /// 是否为图片地址(富文本里的图片已包成 <a href=图片地址>)
    static bool _isImageUrl(String url) {
        final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
        return RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?.*)?$').hasMatch(path) ||
            url.contains('i.mcmod.cn');
    }

    /// 灯箱:全屏暗底放大查看图片,点击任意处或关闭按钮退出,支持缩放
    void _showLightbox(String url) {
        showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        barrierLabel: 'Image Box',
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
            return Stack(
                children: [
                    Positioned.fill(
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: InteractiveViewer(
                        maxScale: 5,
                        child: Center(
                            child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : const CircularProgressIndicator(
                                        color: Colors.white54,
                                        ),
                            errorBuilder: (context, error, stackTrace) =>
                                const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Icon(Icons.broken_image,
                                    color: Colors.white54, size: 64),
                                SizedBox(height: 8),
                                Text(
                                    '图片加载失败',
                                    style: TextStyle(color: Colors.white54),
                                ),
                                ],
                            ),
                            ),
                        ),
                        ),
                    ),
                    ),
                    Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                        ),
                    ),
                ],
            );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        );
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            // 刘海屏
            appBar: AppBar(title: Text(widget.initialTitle ?? '模组详情')),
            body: FutureBuilder<ModDetail>(
                future: _future,
                builder: (context, snapshot) {
                    // 加载界面
                    if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                    }
                    // 错误界面
                    if (snapshot.hasError) {
                        return Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        const Icon(Icons.error_outline, size: 48),
                                        const SizedBox(height: 12),
                                        Text('加载失败\n${snapshot.error}', textAlign: TextAlign.center),
                                        const SizedBox(height: 12),
                                        FilledButton(onPressed: _reload, child: const Text('重试')),
                                    ],
                                ),
                            ),
                        );
                    }
                    return _buildDetail(snapshot.data!);
                }
            ),
        );
    }

    Widget _buildDetail(ModDetail mod) {
        final theme = Theme.of(context);
        return ListView(
            padding: const EdgeInsets.all(16),
            children: [
                if (mod.coverUrl != null) _buildIcon(mod, theme),

                // 模组名称
                const SizedBox(height: 12),
                Text(mod.title, style: theme.textTheme.headlineSmall),
                if (mod.subName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        mod.subName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        ),
                    ),
                ],

                if (mod.platform != null || mod.environment != null) ...[
                    const SizedBox(height: 8),
                    _buildPlatforms(mod),
                ],
                if (mod.links.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('相关链接', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildLinks(mod),
                ],
                if (mod.mcVersions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('支持版本', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildModVersion(mod),
                ],
                if (mod.description != null && mod.description!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('模组介绍', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildDescription(mod, theme),
                ],

                const SizedBox(height: 24),
                OutlinedButton.icon(
                    onPressed: () => _openUrl(mod.pageUrl),
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('在浏览器中打开'),
                ),
            ],
        );
    }

    // 模组图标
    Widget _buildIcon(ModDetail mod, ThemeData theme) {
        return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
                onTap: () => _showLightbox(mod.coverUrl!),
                child: Image.network(
                    mod.coverUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                        height: 200,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported, size: 48),
                    ),
                ),
            ),
        );
    }

    // 支持平台
    Widget _buildPlatforms(ModDetail mod) {
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
                if (mod.platform != null)
                    _InfoChip(label: '平台: ${mod.platform}'),
                if (mod.environment != null)
                    _InfoChip(label: '环境: ${mod.environment}'),
            ],
        );
    }

    // 相关链接
    Widget _buildLinks(ModDetail mod) {
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
                for (final link in mod.links)
                    ActionChip(
                        avatar: Icon(_linkIcon(link.name), size: 18),
                        label: Text(link.name),
                        onPressed: () => _openUrl(link.url),
                    ),
            ],
        );
    }

    // 支持版本
    Widget _buildModVersion(ModDetail mod) {
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
                for (final v in mod.mcVersions) _InfoChip(label: v),
            ],
        );
    }

    // 详细内容
    Widget _buildDescription(ModDetail mod, ThemeData theme) {
        // 富文本渲染:标题、加粗、颜色、图片、表格、列表等。
        // 图片已包成 <a href=图片地址>,点击时走灯箱放大
        return HtmlWidget(
            mod.description!,
            textStyle: theme.textTheme.bodyMedium,
            onTapUrl: (url) {
                if (_isImageUrl(url)) {
                    _showLightbox(url);
                } else {
                    _openUrl(url);
                }
                return true;
            },
        );
    }

    // 选择匹配的图标
    IconData _linkIcon(String name) {
        final n = name.toLowerCase();
        if (n.contains('github')) return Icons.code;
        if (n.contains('discord')) return Icons.forum;
        if (n.contains('curse') || n.contains('forge')) return Icons.extension;
        return Icons.link;
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
