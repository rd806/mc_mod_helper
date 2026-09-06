import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

part 'part/image.dart';
part 'part/inline.dart';
part 'part/span_grid.dart';
part 'part/style.dart';
part 'part/table.dart';

/// 轻量 HTML 渲染器
///
/// fwfh 会为正文里的每个文本块/链接包 MouseRegion(用于光标与
/// 文本选择)，悬停处内容在帧内重建时触发 Flutter MouseTracker 的
/// '_debugDuringDeviceUpdate' 断言(框架长期未修的 debug bug)。
/// 本渲染器只用 Text.rich/Table/Image.network/GestureDetector 等
/// 原生控件构建,整个正文零 MouseRegion,从根源上消除该断言。
///
/// 支持的标签:块级 p/div/h1-h6/ul/ol/li/table/blockquote/pre/
/// details/hr/center;行内 b/strong/i/em/u/del/code/a/img/br/span
/// (样式取 color、background-color、font-weight、font-style、
/// text-decoration、font-size)。表格支持 colspan/rowspan 合并单元格
/// (含合并单元格的表格走自定义网格模型渲染)。含图片的表格(画廊,
/// 如 mcmod 的「截图欣赏」「更多展示」、JEI 物品表)统一按固定
/// 缩略图宽度渲染整表,超出容器时横向滚动。
///
/// 实现按职责拆分在 part 文件 part/ 下:表格(table)、
/// 合并单元格网格(span_grid)、行内(inline)、图片(image)、
/// 样式解析(style);本文件保留入口与块级渲染。
class HtmlContent extends StatelessWidget {
  const HtmlContent({
    super.key,
    required this.html,
    required this.onLinkTap,
    this.textStyle,
  });

  /// 清洗后的 HTML 片段(McmodApi / ModrinthApi 的 description 字段)
  final String html;

  /// 链接/图片点击回调;url 分流(灯箱/浏览器/应用内跳转)由调用方决定
  final void Function(String url) onLinkTap;

  /// 正文基础样式,默认取 bodyMedium
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = textStyle ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final nodes = html_parser.parseFragment(html).nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildBlocks(context, theme, base, nodes, 0, onLinkTap),
    );
  }
}

/// 画廊(含图片表格)的缩略图宽度:配 180 高为 16:9,
/// 整表总宽 = 列数 × 此宽度,超出容器时横向滚动
const double _galleryImageWidth = 320;
const double _galleryImageHeight = 180;
const double _contentImageHeight = 280;

// ---------- 块级 ----------

/// 块级元素列表 → 控件列表(空白文本节点丢弃)
List<Widget> _buildBlocks(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  List<dom.Node> nodes,
  double listDepth,
  void Function(String) onLinkTap,
) {
  final widgets = <Widget>[];
  for (final node in nodes) {
    if (node is dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        widgets.add(_block(Text(text, style: base), bottom: 8));
      }
      continue;
    }
    if (node is! dom.Element) continue;
    final w = _buildBlock(context, theme, base, node, listDepth, onLinkTap);
    if (w != null) widgets.add(w);
  }
  return widgets;
}

/// 单个块级元素 → 控件(无法识别的按行内兜底)
Widget? _buildBlock(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  double listDepth,
  void Function(String) onLinkTap,
) {
  switch (el.localName) {
    case 'p':
    case 'div':
    case 'center':
      return _buildParagraph(context, theme, base, el, onLinkTap);
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      // 标题:按级别放大加粗(与 bbcode [h1=]~[h4=] 的系数一致)
      const sizes = {
        'h1': 1.5,
        'h2': 1.35,
        'h3': 1.2,
        'h4': 1.1,
        'h5': 1.05,
        'h6': 1.0,
      };
      final size = (base.fontSize ?? 14) * sizes[el.localName]!;
      final spans = _buildInline(context, theme, base, el.nodes, onLinkTap);
      return _block(
        Text.rich(
          TextSpan(
            style: base.copyWith(fontSize: size, fontWeight: FontWeight.bold),
            children: spans,
          ),
        ),
        top: 12,
        bottom: 8,
      );
    case 'ul':
    case 'ol':
      return _buildList(context, theme, base, el, listDepth, onLinkTap);
    case 'table':
      return _buildTable(context, theme, base, el, onLinkTap);
    case 'blockquote':
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 4),
          ),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildBlocks(
            context,
            theme,
            base,
            el.nodes,
            listDepth,
            onLinkTap,
          ),
        ),
      );
    case 'pre':
    case 'code':
      // 代码块(pre/markdown 的 <pre><code> 都会走到这里)
      return _buildCodeBlock(context, theme, base, el);
    case 'hr':
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(),
      );
    case 'details':
      // 剧透内容(bbcode [spoiler]):折叠块,点击展开;
      // 不用 ExpansionTile(内部 InkWell 会引入 MouseRegion)
      final summary = el.querySelector('summary')?.text.trim() ?? '展开';
      return _Spoiler(
        summary: summary.isEmpty ? '展开' : summary,
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildBlocks(
            context,
            theme,
            base,
            [
              for (final n in el.nodes)
                if (!(n is dom.Element && n.localName == 'summary')) n,
            ],
            listDepth,
            onLinkTap,
          ),
        ),
      );
    case 'br':
      return const SizedBox(height: 4);
    case 'img':
      // 块级位置的图片(如单元格里 <img><br>文字 的结构,图片未被
      // <a> 包裹):按属性尺寸或自然尺寸渲染,不进入行内兜底
      return _block(
        _image(
          el.attributes['src'] ?? '',
          height: _attrPx(el.attributes['height']) ?? 0,
          width: _attrPx(el.attributes['width']),
        ),
        bottom: 8,
      );
    default:
      // 未知标签(span 等):按行内渲染兜底
      final spans = _buildInline(context, theme, base, el.nodes, onLinkTap);
      if (spans.isEmpty) return null;
      return _block(
        Text.rich(TextSpan(style: base, children: spans)),
        bottom: 8,
      );
  }
}

/// p/div/center:支持 style 的 text-align、margin 与字体设置;
/// 整段只有一张图片时直接渲染图片(行内 WidgetSpan 无法占满宽度)
Widget _buildParagraph(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  void Function(String) onLinkTap,
) {
  final src = _imageOnlySrc(el);
  if (src != null) {
    return _blockImage(
      src,
      height: _contentImageHeight,
      onTap: () => onLinkTap(src),
    );
  }
  final style = _parseBlockStyle(el.attributes['style']);
  final align = el.localName == 'center' ? TextAlign.center : style.align;
  final pBase = base.copyWith(
    fontSize: (base.fontSize ?? 14) * style.fontSizeFactor,
    fontWeight: style.bold ? FontWeight.bold : base.fontWeight,
  );
  final spans = _buildInline(context, theme, pBase, el.nodes, onLinkTap);
  if (spans.isEmpty) return const SizedBox(height: 8);
  return _block(
    Text.rich(
      TextSpan(style: pBase, children: spans),
      textAlign: align,
    ),
    top: style.marginTop,
    bottom: 8 + style.marginBottom,
  );
}

/// 代码块(pre / 块级 code):按行渲染、不自动换行。
///
/// 换行识别：`<br>` 与文本里的 `\n` 都算换行(mcmod 的代码块用 `<br>`
/// 分行、`&nbsp;` 缩进；markdown 转出的 `<pre><code>` 用 `\n` 分行)。
///
/// 整块包横向滚动容器：长行超出容器时左右滚动查看(桌面端支持鼠标拖拽),
/// 而不是被折行压乱格式。
Widget _buildCodeBlock(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
) {
  final style = _monoStyle(theme, base);
  final lines = _codeLines(el);
  final block = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in lines) Text(line, style: style, softWrap: false),
    ],
  );
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    // 横向滚动容器:内容自然宽,超出容器宽度时左右滚动
    child: _wrapTableScroll(context, block),
  );
}

/// 提取代码块的行：递归收集文本,`<br>` 与 `\n` 都算换行;
/// `&nbsp;`(`U+00A0`)转成普通空格,等宽字体下缩进才能对齐
List<String> _codeLines(dom.Element el) {
  final lines = <String>[];
  var current = StringBuffer();
  void flush() {
    lines.add(current.toString().replaceAll(' ', ' '));
    current = StringBuffer();
  }

  void walk(List<dom.Node> nodes) {
    for (final n in nodes) {
      if (n is dom.Text) {
        final parts = n.text.split('\n');
        current.write(parts.first);
        for (final part in parts.skip(1)) {
          flush();
          current.write(part);
        }
      } else if (n is dom.Element) {
        if (n.localName == 'br') {
          flush();
        } else {
          // 嵌套元素(如 markdown 的 <pre><code>):递归取文本
          walk(n.nodes);
        }
      }
    }
  }

  walk(el.nodes);
  flush();
  return lines;
}

/// 列表:每个条目一行,无序用圆点、有序用序号;嵌套列表按层级缩进
Widget _buildList(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  double listDepth,
  void Function(String) onLinkTap,
) {
  final ordered = el.localName == 'ol';
  final items = el.children.whereType<dom.Element>().where(
    (c) => c.localName == 'li',
  );
  var index = 0;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final li in items)
          Padding(
            padding: EdgeInsets.only(left: 16 * listDepth, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Text(ordered ? '${++index}.' : '•', style: base),
                ),
                Expanded(
                  child: _richContent(
                    context,
                    theme,
                    base,
                    li,
                    listDepth + 1,
                    onLinkTap,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// 块级间距包装
Widget _block(Widget child, {double top = 0, double bottom = 0}) {
  return Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: child,
  );
}

/// 剧透折叠块([spoiler] 产出):点击标题展开/收起。
///
/// 不用 ExpansionTile:其内部 InkWell 会引入 MouseRegion,
/// 与零 MouseRegion 的目标冲突。
class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.summary, required this.builder});

  final String summary;
  final WidgetBuilder builder;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: widget.builder(context),
            ),
        ],
      ),
    );
  }
}
