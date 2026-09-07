part of '../html_content.dart';

// ---------- 图片 ----------

/// 图片:给定 [width] 时为固定宽盒(块级图片传 double.infinity 占满行宽),
/// 为 null 时按自然宽度(行内图标/头像)。
/// 占位尺寸必须有界:行内图片在段落里参与固有宽度测量,
/// 无限宽会让 TextPainter 断言 'maxIntrinsicLineExtent.isFinite' 失败
Widget _image(
  String url, {
  required double height,
  double? width,
  VoidCallback? onTap,
}) {
  final placeholderHeight = height <= 0 ? 24.0 : height;
  final placeholderWidth = width ?? placeholderHeight;
  final img = Image.network(
    url,
    fit: BoxFit.contain,
    width: width,
    height: height <= 0 ? null : height,
    // 加载中占位:保持固定尺寸,加载前后不引起布局移动
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : SizedBox(
            height: placeholderHeight,
            width: placeholderWidth,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
    errorBuilder: (context, error, stackTrace) => SizedBox(
      height: placeholderHeight,
      width: placeholderWidth,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: placeholderHeight > 60 ? 40 : 20,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    ),
  );
  if (onTap == null) return img;
  // 只用 GestureDetector(仅 onTap 不产生 MouseRegion),点击走灯箱
  return GestureDetector(onTap: onTap, child: img);
}

/// 块级单图:上下留白 + 灯箱点击
Widget _blockImage(
  String url, {
  required double height,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: _image(url, height: height, width: double.infinity, onTap: onTap),
  );
}

/// 元素是否整块只有一张图片(画廊单元格/正文配图的判定依据)
String? _imageOnlySrc(dom.Element el) {
  if (el.text.trim().isNotEmpty) return null;
  final imgs = el.querySelectorAll('img');
  if (imgs.length != 1) return null;
  final src = imgs.first.attributes['src']?.trim();
  return (src == null || src.isEmpty) ? null : src;
}

/// 图注格:单张图片 + 图下方说明文字(画廊常见结构
/// `<a><img></a><br>说明`),与 JEI 的同行混排(`<a><img></a>物品名`)
/// 区分:图片与文字之间隔着块级换行才算图注
String? _captionImageSrc(dom.Element el) {
  if (el.text.trim().isEmpty) return null; // 纯图格走 _imageOnlySrc
  final imgs = el.querySelectorAll('img');
  if (imgs.length != 1) return null;
  final src = imgs.first.attributes['src']?.trim() ?? '';
  if (src.isEmpty) return null;
  // 信号 1:站点图注结构 <span class="figcaption">说明</span>
  // (mcmod 画廊「更多展示」,图片与文字同包在 span.figure 里,
  // 没有块级换行分隔)
  if (el.querySelector('.figcaption') != null) return src;
  // 信号 2:图片与文字之间隔着块级换行(其他画廊结构
  // <a><img></a><br>说明)
  // 图片所在的顶层节点(裸 img 或 a/p/div 包裹)
  dom.Node? top;
  for (final n in el.nodes) {
    if (n is dom.Element && n.querySelector('img') != null) {
      top = n;
      break;
    }
  }
  if (top == null) return null;
  // 图片之前不能有非空白文本(同行混排,如物品名在图片前)
  var seen = false;
  for (final n in el.nodes) {
    if (!seen) {
      if (identical(n, top)) {
        seen = true;
      } else if (n is dom.Text && n.text.trim().isNotEmpty) {
        return null;
      } else if (n is dom.Element && n.querySelector('img') == null) {
        return null; // 图片前的兄弟元素,视为混排
      }
      continue;
    }
    // 图片之后:直接跟同行文本 → JEI 混排;块级换行 → 图注
    if (n is dom.Text) {
      if (n.text.trim().isEmpty) continue;
      return null;
    }
    if (n is dom.Element && _captionBreaks.contains(n.localName)) {
      return src;
    }
  }
  return null;
}

/// 图注格中图片之外的说明内容(去掉图片节点与紧随其后的换行)
List<Widget> _captionBlocks(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element cell,
  void Function(String) onLinkTap,
) {
  // 站点图注结构:取 figcaption 的文本,居中显示在图片下方。
  // 占满行宽才能让 textAlign.center 对单行文字生效
  // (Text 只有内容宽时居中不改变视觉位置)
  final figcaption = cell.querySelector('.figcaption');
  if (figcaption != null) {
    final text = figcaption.text.trim();
    if (text.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ];
  }
  // 块级换行结构:图片之后的顶层节点(去掉紧随的换行占位),
  // 说明内容在图片下方水平居中
  final nodes = _splitFigure(cell).after;
  if (nodes.isNotEmpty &&
      nodes.first is dom.Element &&
      (nodes.first as dom.Element).localName == 'br') {
    nodes.removeAt(0);
  }
  return [
    SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _buildBlocks(context, theme, base, nodes, 0, onLinkTap),
      ),
    ),
  ];
}

/// 按图片所在节点把顶层节点拆成 之前/之后 两组。
///
/// 站点有时把小节标题与配图放在同一段里(如 class/18075 的「合影」
/// 配图后紧跟「概述」标题),配图两侧的兄弟节点需要单独成块渲染
({List<dom.Node> before, List<dom.Node> after}) _splitFigure(dom.Element el) {
  final before = <dom.Node>[];
  final after = <dom.Node>[];
  var seen = false;
  for (final n in el.nodes) {
    if (!seen && n is dom.Element && n.querySelector('img') != null) {
      seen = true;
      continue;
    }
    (seen ? after : before).add(n);
  }
  return (before: before, after: after);
}

/// 图注的块级分隔标签(说明文字位于图片下方的标志)
const Set<String> _captionBreaks = {
  'br',
  'p',
  'div',
  'center',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// 块级标签集合(单元格/列表项内容走块列表还是纯文本的判定)
bool _isBlockTag(dom.Element el) => const {
  'p',
  'div',
  'ul',
  'ol',
  'table',
  'blockquote',
  'pre',
  'details',
  'hr',
  'center',
  'br',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
}.contains(el.localName);
