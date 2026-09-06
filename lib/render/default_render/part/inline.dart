part of '../html_content.dart';

// ---------- 行内 ----------

/// 行内节点列表 → InlineSpan 列表
List<InlineSpan> _buildInline(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  List<dom.Node> nodes,
  void Function(String) onLinkTap,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) {
        // 与 HTML 渲染一致:连续空白折叠为单个空格
        spans.add(TextSpan(text: node.text.replaceAll(RegExp(r'\s+'), ' ')));
      }
      continue;
    }
    if (node is! dom.Element) continue;
    final span = _buildInlineElement(context, theme, base, node, onLinkTap);
    if (span != null) spans.add(span);
  }
  return spans;
}

/// 单个行内元素 → InlineSpan(无法识别的透传子节点)
InlineSpan? _buildInlineElement(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  void Function(String) onLinkTap,
) {
  TextStyle? style;
  switch (el.localName) {
    case 'b':
    case 'strong':
      style = const TextStyle(fontWeight: FontWeight.bold);
      break;
    case 'i':
    case 'em':
      style = const TextStyle(fontStyle: FontStyle.italic);
      break;
    case 'u':
      style = const TextStyle(decoration: TextDecoration.underline);
      break;
    case 'del':
    case 's':
    case 'strike':
      style = const TextStyle(decoration: TextDecoration.lineThrough);
      break;
    case 'code':
      style = _monoStyle(
        theme,
        base,
      ).copyWith(fontSize: (base.fontSize ?? 14) * 0.9);
      break;
    case 'br':
      return const TextSpan(text: '\n');
    case 'img':
      // 行内图片(头像、图标与文字混排):带宽高属性时按属性尺寸
      // (如贡献者表格的 100px 头像),否则自然尺寸。
      // 宽度必须有界:无限宽会触发固有宽度测量的框架断言
      final w = _attrPx(el.attributes['width']);
      final h = _attrPx(el.attributes['height']);
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _image(el.attributes['src'] ?? '', height: h ?? 0, width: w),
      );
    case 'a':
      // 链接:TextSpan recognizer 处理点击,不包 MouseRegion。
      // 注意:RenderParagraph 命中测试只把字形所在的最深层 span 加入
      // 命中路径,识别器必须挂在叶子文本 span 上才生效
      final href = el.attributes['href'] ?? '';
      final recognizer = TapGestureRecognizer()..onTap = () => onLinkTap(href);
      final children = _attachRecognizer(
        _buildInline(context, theme, base, el.nodes, onLinkTap),
        recognizer,
      );
      return TextSpan(
        style: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        children: children,
      );
    case 'span':
      style = _parseInlineStyle(el.attributes['style'], base);
      break;
  }
  if (style == null) {
    return TextSpan(
      children: _buildInline(context, theme, base, el.nodes, onLinkTap),
    );
  }
  return TextSpan(
    style: style,
    children: _buildInline(context, theme, base, el.nodes, onLinkTap),
  );
}

/// 把识别器挂到子树里每个叶子文本 span 上(仅复制 text/style/children)
List<InlineSpan> _attachRecognizer(
  List<InlineSpan> spans,
  TapGestureRecognizer recognizer,
) {
  return [
    for (final span in spans)
      if (span is TextSpan)
        TextSpan(
          text: span.text,
          style: span.style,
          recognizer: span.children == null || span.children!.isEmpty
              ? recognizer
              : span.recognizer,
          children: span.children == null
              ? null
              : _attachRecognizer(span.children!, recognizer),
        )
      else
        span,
  ];
}

/// 单元格/列表项内容:含块级子元素 → 块列表,否则 → 纯文本
Widget _richContent(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  double listDepth,
  void Function(String) onLinkTap,
) {
  if (el.children.whereType<dom.Element>().any(_isBlockTag)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildBlocks(
        context,
        theme,
        base,
        el.nodes,
        listDepth,
        onLinkTap,
      ),
    );
  }
  return Text.rich(
    TextSpan(
      style: base,
      children: _buildInline(context, theme, base, el.nodes, onLinkTap),
    ),
  );
}
