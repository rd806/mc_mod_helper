import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:mc_mod_helper/render/default_render/html_content.dart';
import 'package:mc_mod_helper/render/hyper_render/hyper.dart';
import 'package:mc_mod_helper/service/settings.dart';
import 'package:mc_mod_helper/service/value/render.dart';

import '../../model/mod/mod_detail.dart';
import 'section_title.dart';

/// 模组介绍:渲染清洗后的 HTML 正文(两种来源的描述都是清洗后的 HTML)。
///
/// 按设置里的渲染方法二选一:
/// - default:自写 HtmlContent(逐标签映射控件,正文零 MouseRegion)
/// - hyperViewer:hyper_render(单 RenderObject 布局引擎,性能更优)
class DescriptionCard extends StatelessWidget {
  const DescriptionCard({
    super.key,
    required this.mod,
    required this.onLinkTap,
  });

  final ModDetail mod;

  /// 正文链接/图片点击回调(灯箱/站内跳转/浏览器由调用方分流)
  final void Function(String url) onLinkTap;

  @override
  Widget build(BuildContext context) {
    if (mod.body == null || mod.body!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DetailSectionTitle(
              title: '模组介绍',
              icon: Icons.article_rounded,
            ),
            _buildHTML(context),
          ],
        ),
      ),
    );
  }

  /// 按渲染方法选择正文渲染器
  Widget _buildHTML(BuildContext context) {
    final theme = Theme.of(context);
    RenderType type = SettingsService.instance.renderType;
    switch (type) {
      case RenderType.auto:
        return HtmlContent(
          html: mod.body!,
          textStyle: theme.textTheme.bodyMedium,
          onLinkTap: onLinkTap,
        );
      case RenderType.hyper:
        return _mouseDraggable(
          context,
          HyperViewer(
            html: mod.body!,
            mode: HyperRenderMode.sync,
            shrinkWrap: true,
            selectable: false,
            customCss: HyperRender.hyperCss(theme),
            onLinkTap: onLinkTap,
          ),
        );
    }
  }

  /// 桌面端 ScrollBehavior 默认只认触摸/手写笔拖拽,鼠标拖不动
  /// 正文里表格的横向滚动容器;包一层开启鼠标/触控板拖拽的配置
  /// (只作用于描述内容,不影响外层列表的既有滚动方式)
  Widget _mouseDraggable(BuildContext context, Widget widget) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.invertedStylus,
        },
      ),
      child: widget,
    );
  }
}
