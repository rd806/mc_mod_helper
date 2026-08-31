import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/mod.dart';
import '../api/mcmod.dart';
import '../widget/collapsible_chips.dart';
import '../widget/link_icons.dart';
import '../widget/image_box.dart';

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

    /// 打开链接:站内模组页(class/{id}.html)默认在应用内跳转详情页,其余链接用浏览器打开。
    /// [forceExternal] 为 true 时一律走浏览器
    Future<void> _openUrl(String url, {bool forceExternal = false}) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        if (!forceExternal) {
            final modId = _modIdFromUrl(uri);
            if (modId != null) {
                // 跳过指向当前模组自身的链接,避免堆叠重复详情页
                if (modId == widget.id) return;
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetailPage(id: modId)),
                );
                return;
            }
        }
        try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')),);
            }
        }
    }

    /// 站内模组详情页链接(www.mcmod.cn/class/{id}.html) → 模组 id;
    /// 其它链接返回 null
    static int? _modIdFromUrl(Uri uri) {
        if (uri.host != 'www.mcmod.cn' && uri.host != 'mcmod.cn') return null;
        final m = RegExp(r'^/class/(\d+)\.html$').firstMatch(uri.path);
        return m == null ? null : int.parse(m.group(1)!);
    }

    /// 是否为图片地址(富文本里的图片已包成 <a href=图片地址>)
    static bool _isImageUrl(String url) {
        final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
        return RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?.*)?$').hasMatch(path) ||
            url.contains('i.mcmod.cn');
    }

    /// 灯箱:全屏暗底放大查看图片,点击任意处或关闭按钮退出,支持缩放
    void _showLightbox(String url) {
        showImageBox(context, url);
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            // 刘海屏
            appBar: AppBar(
                title: Text(widget.initialTitle ?? '模组详情'),
                actions: [
                    IconButton(
                        tooltip: '刷新',
                        icon: const Icon(Icons.refresh),
                        onPressed: _reload,
                    ),
                    // 页地址只依赖 id，详情未加载完也能打开
                    IconButton(
                        tooltip: '在浏览器中打开',
                        icon: const Icon(Icons.open_in_browser),
                        onPressed: () => _openUrl(
                            'https://www.mcmod.cn/class/${widget.id}.html',
                            forceExternal: true,
                        ),
                    ),
                ],
            ),
            body: FutureBuilder<ModDetail>(
                future: _future,
                builder: (context, snapshot) {
                    // 加载界面
                    if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                    }
                    // 错误界面
                    if (snapshot.hasError) {
                        return _buildErrorPage(snapshot);
                    }
                    // 详情界面
                    return _buildDetail(snapshot.data!);
                }
            ),
        );
    }

    // 错误界面
    Widget _buildErrorPage(AsyncSnapshot<ModDetail> snapshot) {
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

    // 详情界面
    Widget _buildDetail(ModDetail mod) {
        final theme = Theme.of(context);
        return ListView(
            padding: const EdgeInsets.all(16),
            children: [
                if (mod.coverUrl != null) _buildIcon(mod, theme),

                // 模组名称
                const SizedBox(height: 12),
                Text(mod.title, style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold
                )),
                if (mod.subName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        mod.subName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontStyle: FontStyle.italic
                        ),
                    ),
                ],

                if (mod.platform != null || mod.environment != null) ...[
                    const SizedBox(height: 16),
                    _buildPlatforms(mod),
                    const SizedBox(height: 16),
                ],
                const Divider(),
                if (mod.links.isNotEmpty) ...[
                    _buildSectionTitle('相关链接', Icons.insert_link_rounded),
                    _buildLinks(mod),
                ],
                const Divider(),
                if (mod.mcVersions.isNotEmpty) ...[
                    _buildSectionTitle('支持版本', Icons.check_circle_rounded),
                    _buildModVersion(mod),
                ],
                const Divider(),
                if (mod.description != null && mod.description!.isNotEmpty) ...[
                    _buildSectionTitle('模组介绍', Icons.article_rounded),
                    _buildDescription(mod, theme),
                ],
            ],
        );
    }

    /// 区块标题:上间距 + titleLarge 标题 + 下间距,配合 ... 展开使用
    Widget _buildSectionTitle(String title, IconData icon) {
        return Padding(
            // 上下间距写入 Padding 中
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Row(
                children: [
                    Icon(icon),
                    const SizedBox(width: 5),
                    Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold
                        )
                    ),
                ]
            ),
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
        return CollapsibleChips(
            chips: [
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
        return CollapsibleChips(
            chips: [for (final v in mod.mcVersions) _InfoChip(label: v)],
        );
    }

    // 详细内容
    Widget _buildDescription(ModDetail mod, ThemeData theme) {
        // 富文本渲染:标题、加粗、颜色、图片、表格、列表等。
        // 图片已包成 <a href=图片地址>，点击时走灯箱放大
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

    // 选择匹配的品牌图标(自定义图标字体),没有匹配时用通用链接图标
    IconData _linkIcon(String name) {
        final n = name.toLowerCase();
        if (n.contains('github')) return LinkIcons.github;
        if (n.contains('discord')) return LinkIcons.discord;
        if (n.contains('patreon')) return LinkIcons.patreon;
        if (n.contains('wiki')) return LinkIcons.wiki;
        if (n.contains('youtube')) return LinkIcons.youtube;
        if (n.contains('curse') || n.contains('forge')) return LinkIcons.curseforge;
        if (n.contains('mcbbs') || n.contains('bbs')) return LinkIcons.mcbbs;
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
