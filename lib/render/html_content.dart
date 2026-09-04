import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 轻量 HTML 渲染器：替代 flutter_widget_from_html。
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
/// (含合并单元格的表格走自定义网格模型渲染)。
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
      children: _buildBlocks(context, theme, base, nodes, 0),
    );
  }

  // ---------- 块级 ----------

  /// 块级元素列表 → 控件列表(空白文本节点丢弃)
  List<Widget> _buildBlocks(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    List<dom.Node> nodes,
    double listDepth,
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
      final w = _buildBlock(context, theme, base, node, listDepth);
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
  ) {
    switch (el.localName) {
      case 'p':
      case 'div':
      case 'center':
        return _buildParagraph(context, theme, base, el);
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
        final spans = _buildInline(context, theme, base, el.nodes);
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
        return _buildList(context, theme, base, el, listDepth);
      case 'table':
        return _buildTable(context, theme, base, el);
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
            children: _buildBlocks(context, theme, base, el.nodes, listDepth),
          ),
        );
      case 'pre':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(el.text, style: _monoStyle(theme, base)),
        );
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
            children: _buildBlocks(context, theme, base, [
              for (final n in el.nodes)
                if (!(n is dom.Element && n.localName == 'summary')) n,
            ], listDepth),
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
        final spans = _buildInline(context, theme, base, el.nodes);
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
    final spans = _buildInline(context, theme, pBase, el.nodes);
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

  /// 列表:每个条目一行,无序用圆点、有序用序号;嵌套列表按层级缩进
  Widget _buildList(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    dom.Element el,
    double listDepth,
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
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 表格:原生 Table 渲染。
  ///
  /// - 纯文字表格:TableBorder.all 单线框线,表头加粗居中;
  /// - 画廊(存在只含图片的单元格):等宽列、无框线、图片固定高度,
  ///   加载完成前就占据固定行高,不引起纵向布局移动。
  /// colspan/rowspan 不支持(与 fwfh 行为一致,单元格按顺序渲染)。
  Widget _buildTable(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    dom.Element el,
  ) {
    // 每行收集 td/th 单元格。
    // 注意:解析器会为表格插入 tbody/thead 包装,tr 必须是后代而非直接子节点
    final rows = [
      for (final tr in el.querySelectorAll('tr'))
        [
          for (final c in tr.children.whereType<dom.Element>())
            if (c.localName == 'td' || c.localName == 'th') c,
        ],
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    // 画廊判定:存在只含图片的单元格,或单图+图下说明的图注格
    final isGallery = rows.any(
      (r) =>
          r.any((c) => _imageOnlySrc(c) != null || _captionImageSrc(c) != null),
    );
    // 合并单元格(rowspan/colspan):Table 控件不支持,
    // 改用自定义网格模型渲染(见 _buildSpanGrid)
    final hasSpan = rows.any(
      (r) => r.any((c) {
        final rs = int.tryParse(c.attributes['rowspan'] ?? '');
        final cs = int.tryParse(c.attributes['colspan'] ?? '');
        return (rs != null && rs > 1) || (cs != null && cs > 1);
      }),
    );
    if (hasSpan) {
      return _buildSpanGrid(context, theme, base, rows, colCount, isGallery);
    }
    final table = Table(
      columnWidths: isGallery
          // 画廊:等宽列,图片随容器缩放
          ? {for (var i = 0; i < colCount; i++) i: const FlexColumnWidth(1)}
          // 文字表格:每列按内容自然宽度(上限 240px,过长才在列内换行)。
          // 多列表格(如 JEI 的物品表)列宽不再被等分压窄
          : {
              for (var i = 0; i < colCount; i++)
                i: const _CappedIntrinsicColumnWidth(240),
            },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      // 画廊与文字表格统一单线框线(TableBorder.all 一条边只画一次)
      border: TableBorder.all(color: theme.colorScheme.outlineVariant),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < colCount; i++)
                if (i < row.length)
                  _buildCell(context, theme, base, row[i], isGallery)
                else
                  const TableCell(child: SizedBox()),
            ],
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isGallery
          ? table
          // 文字表格:总宽超过容器时横向滚动(桌面端支持鼠标拖拽)
          : _wrapTableScroll(context, table),
    );
  }

  /// 文字表格的横向滚动容器:表格总宽超过容器时左右滚动,
  /// 桌面端 ScrollBehavior 默认不认鼠标拖拽,补上鼠标/触控板
  Widget _wrapTableScroll(BuildContext context, Widget table) {
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
    );
  }

  /// 单元格:整格单张图片(画廊)→ 固定高度图片;
  /// 其余 → 纯行内走文本、含块级子元素走块列表;th 加粗居中
  Widget _buildCell(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    dom.Element cell,
    bool isGallery,
  ) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: _cellContent(context, theme, base, cell, isGallery),
      ),
    );
  }

  /// 单元格内容构建(Table 路径与合并单元格网格路径共用)
  Widget _cellContent(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    dom.Element cell,
    bool isGallery,
  ) {
    final src = _imageOnlySrc(cell);
    if (src != null) {
      return _image(
        src,
        height: isGallery ? _galleryImageHeight : _contentImageHeight,
        width: double.infinity,
        onTap: () => onLinkTap(src),
      );
    }
    // 图注格:单图 + 图下方说明文字 → 图片可点灯箱,说明渲染在下方
    final captionSrc = _captionImageSrc(cell);
    if (captionSrc != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _image(
            captionSrc,
            height: isGallery ? _galleryImageHeight : _contentImageHeight,
            width: double.infinity,
            onTap: () => onLinkTap(captionSrc),
          ),
          ..._captionBlocks(context, theme, base, cell),
        ],
      );
    }
    if (cell.children.whereType<dom.Element>().any(_isBlockTag)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildBlocks(context, theme, base, cell.nodes, 0),
      );
    }
    if (cell.localName == 'th') {
      return Text.rich(
        TextSpan(
          style: base.copyWith(fontWeight: FontWeight.bold),
          children: _buildInline(context, theme, base, cell.nodes),
        ),
        textAlign: TextAlign.center,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: _buildInline(context, theme, base, cell.nodes),
      ),
    );
  }

  /// 含合并单元格(rowspan/colspan)的表格:Flutter 的 Table 不支持,
  /// 改用「IntrinsicHeight(Row) + 定宽单元格」网格模型渲染。
  ///
  /// - 列宽:每列按内容自然宽(文本用 TextPainter 实测、图片取属性宽,
  ///   横向合并格的内容宽按列数均摊),单列上限 240px——与文字表格
  ///   路径一致,多列表格列宽不被压窄;
  /// - 横向合并:单元格宽 = 所跨列宽之和,天然对齐;
  /// - 纵向合并:锚定格画内容,下方各行用带边线的占位格延续单元格轮廓
  ///   (只画左右边线、最后一行补底边线),视觉上就是一个合并单元格;
  /// - 整表按内容自然宽布局,超出容器时横向滚动(桌面端支持鼠标拖拽)。
  Widget _buildSpanGrid(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    List<List<dom.Element>> rows,
    int colCount,
    bool isGallery,
  ) {
    // 1. 按 rowspan/colspan 填充占用网格,收集锚定格
    final occupied = List.generate(
      rows.length,
      (_) => List.filled(colCount, false),
    );
    final placed = <_GridCell>[];
    for (var r = 0; r < rows.length; r++) {
      var c = 0;
      for (final cell in rows[r]) {
        // 跳过被上方合并单元格占用的位置
        while (c < colCount && occupied[r][c]) {
          c++;
        }
        if (c >= colCount) break; // 畸形行:超出列数,丢弃多余单元格
        final rs = int.tryParse(cell.attributes['rowspan'] ?? '');
        final cs = int.tryParse(cell.attributes['colspan'] ?? '');
        final rowSpan = (rs == null || rs < 1) ? 1 : rs;
        final colSpan = (cs == null || cs < 1) ? 1 : cs;
        for (var rr = r; rr < r + rowSpan && rr < rows.length; rr++) {
          for (var cc = c; cc < c + colSpan && cc < colCount; cc++) {
            occupied[rr][cc] = true;
          }
        }
        placed.add(
          _GridCell(
            el: cell,
            row: r,
            col: c,
            rowSpan: rowSpan,
            colSpan: colSpan,
          ),
        );
        c += colSpan;
      }
    }

    // 2. 列自然宽度:每列取所覆盖单元格的最大内容宽
    //    (文本用 TextPainter 实测、图片取属性宽),加左右内边距,
    //    单列上限 240px——与文字表格路径的列宽规则一致
    double cellWidth(dom.Element el) {
      // 文本自然宽(多行取最长行)
      final tp = TextPainter(
        text: TextSpan(text: el.text.trim(), style: base),
        textDirection: TextDirection.ltr,
      )..layout();
      var w = tp.width;
      // 图片:取属性宽(如 100px 头像),无属性按图标尺寸兜底
      for (final img in el.querySelectorAll('img')) {
        final a = _attrPx(img.attributes['width']);
        final iw = a ?? 24.0;
        if (iw > w) w = iw;
      }
      return w;
    }

    final colWidth = List.generate(colCount, (c) {
      var w = 0.0;
      for (final cell in placed) {
        if (cell.col <= c && c < cell.col + cell.colSpan) {
          // 横向合并格的内容宽按列数均摊到各列
          final share = cellWidth(cell.el) / cell.colSpan;
          if (share > w) w = share;
        }
      }
      return (w + 12).clamp(24.0, 240.0); // + 单元格左右内边距 6*2
    });
    double cellTotal(_GridCell cell) => colWidth
        .sublist(cell.col, cell.col + cell.colSpan)
        .fold(0.0, (a, b) => a + b);

    // 3. 边框:外框画上/左边线,单元格只画右/底边线,
    //    相邻单元格共线呈现单线;合并单元格内部不画线
    final side = BorderSide(color: theme.colorScheme.outlineVariant);
    Widget cellBox(_GridCell cell) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          // 纵向合并的锚定格不画底边(由占位格延续轮廓)
          border: Border(
            right: side,
            bottom: cell.rowSpan == 1 ? side : BorderSide.none,
          ),
        ),
        child: Center(
          child: _cellContent(context, theme, base, cell.el, isGallery),
        ),
      );
    }

    Widget placeholder(_GridCell anchor, int r) {
      final isLastRow = anchor.row + anchor.rowSpan - 1 == r;
      return Container(
        decoration: BoxDecoration(
          border: Border(
            right: side,
            bottom: isLastRow ? side : BorderSide.none,
          ),
        ),
      );
    }

    _GridCell? anchorAt(int r, int c) {
      for (final cell in placed) {
        if (cell.row < r &&
            cell.row + cell.rowSpan > r &&
            cell.col <= c &&
            cell.col + cell.colSpan > c) {
          return cell;
        }
      }
      return null;
    }

    // 单行单元格序列:锚定格 → 内容格;被上方合并覆盖的位置 → 占位格。
    // 每格按所跨列宽之和定宽,整表按内容自然宽布局,
    // 超出容器时由外层横向滚动容器兜底
    List<Widget> rowCells(int r) {
      final children = <Widget>[];
      var c = 0;
      while (c < colCount) {
        _GridCell? cell;
        for (final p in placed) {
          if (p.row == r && p.col == c) {
            cell = p;
            break;
          }
        }
        if (cell != null) {
          c += cell.colSpan;
          children.add(SizedBox(width: cellTotal(cell), child: cellBox(cell)));
        } else {
          final anchor = anchorAt(r, c);
          final span = anchor?.colSpan ?? 1; // 兜底:畸形表格按 1 列
          c += span;
          children.add(
            SizedBox(
              width: anchor == null ? colWidth[0] : cellTotal(anchor),
              child: anchor == null ? const SizedBox() : placeholder(anchor, r),
            ),
          );
        }
      }
      return children;
    }

    final grid = Container(
      decoration: BoxDecoration(
        border: Border(top: side, left: side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var r = 0; r < rows.length; r++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowCells(r),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _wrapTableScroll(context, grid),
    );
  }

  // ---------- 行内 ----------

  /// 行内节点列表 → InlineSpan 列表
  List<InlineSpan> _buildInline(
    BuildContext context,
    ThemeData theme,
    TextStyle base,
    List<dom.Node> nodes,
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
      final span = _buildInlineElement(context, theme, base, node);
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
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onLinkTap(href);
        final children = _attachRecognizer(
          _buildInline(context, theme, base, el.nodes),
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
      return TextSpan(children: _buildInline(context, theme, base, el.nodes));
    }
    return TextSpan(
      style: style,
      children: _buildInline(context, theme, base, el.nodes),
    );
  }

  /// 把识别器挂到子树里每个叶子文本 span 上(仅复制 text/style/children)
  static List<InlineSpan> _attachRecognizer(
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
  ) {
    if (el.children.whereType<dom.Element>().any(_isBlockTag)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildBlocks(context, theme, base, el.nodes, listDepth),
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: _buildInline(context, theme, base, el.nodes),
      ),
    );
  }

  // ---------- 图片 ----------

  static const double _galleryImageHeight = 180;
  static const double _contentImageHeight = 280;

  /// 解析 '100px'/'100px;' 形式的宽高属性为数值,非法返回 null
  static double? _attrPx(String? value) {
    if (value == null) return null;
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
    return m == null ? null : double.parse(m.group(0)!);
  }

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
  static String? _imageOnlySrc(dom.Element el) {
    if (el.text.trim().isNotEmpty) return null;
    final imgs = el.querySelectorAll('img');
    if (imgs.length != 1) return null;
    final src = imgs.first.attributes['src']?.trim();
    return (src == null || src.isEmpty) ? null : src;
  }

  /// 图注格:单张图片 + 图下方说明文字(画廊常见结构
  /// `<a><img></a><br>说明`),与 JEI 的同行混排(`<a><img></a>物品名`)
  /// 区分:图片与文字之间隔着块级换行才算图注
  static String? _captionImageSrc(dom.Element el) {
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
  ) {
    // 站点图注结构:取 figcaption 的文本,居中显示在图片下方
    final figcaption = cell.querySelector('.figcaption');
    if (figcaption != null) {
      final text = figcaption.text.trim();
      if (text.isEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    // 块级换行结构:图片之后的顶层节点(去掉紧随的换行占位)
    final nodes = <dom.Node>[];
    var seen = false;
    for (final n in cell.nodes) {
      if (!seen) {
        if (n is dom.Element && n.querySelector('img') != null) {
          seen = true;
        }
        continue;
      }
      nodes.add(n);
    }
    // 图片与说明之间的换行占位直接丢弃
    if (nodes.isNotEmpty &&
        nodes.first is dom.Element &&
        (nodes.first as dom.Element).localName == 'br') {
      nodes.removeAt(0);
    }
    return _buildBlocks(context, theme, base, nodes, 0);
  }

  /// 图注的块级分隔标签(说明文字位于图片下方的标志)
  static const Set<String> _captionBreaks = {
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

  static bool _isBlockTag(dom.Element el) => const {
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

  // ---------- 样式解析 ----------

  /// 块级 style 解析:text-align、margin(px)、font-size(em/%)、font-weight
  static ({
    TextAlign? align,
    double marginTop,
    double marginBottom,
    double fontSizeFactor,
    bool bold,
  })
  _parseBlockStyle(String? css) {
    final align = _matchCss(css, 'text-align');
    final margin = _parseMargin(_matchCss(css, 'margin'));
    final size = _parseFontFactor(_matchCss(css, 'font-size'));
    return (
      align: align == 'center'
          ? TextAlign.center
          : align == 'right'
          ? TextAlign.right
          : align == 'left'
          ? TextAlign.left
          : null,
      marginTop: margin.$1,
      marginBottom: margin.$2,
      fontSizeFactor: size,
      bold: _matchCss(css, 'font-weight') == 'bold',
    );
  }

  /// 行内 style 解析:颜色/背景色/粗细/斜体/下划线/删除线/字号
  static TextStyle? _parseInlineStyle(String? css, TextStyle base) {
    if (css == null || css.isEmpty) return null;
    final color = _parseColor(_matchCss(css, 'color'));
    final background = _parseColor(_matchCss(css, 'background-color'));
    final weight = _matchCss(css, 'font-weight') == 'bold'
        ? FontWeight.bold
        : null;
    final italic = _matchCss(css, 'font-style') == 'italic' ? true : null;
    final decoration = _matchCss(css, 'text-decoration');
    final size = _parseFontFactor(_matchCss(css, 'font-size'));
    final style = TextStyle(
      color: color,
      backgroundColor: background,
      fontWeight: weight,
      fontStyle: italic == true ? FontStyle.italic : null,
      decoration: decoration == 'underline'
          ? TextDecoration.underline
          : decoration == 'line-through'
          ? TextDecoration.lineThrough
          : null,
      fontSize: size > 0 ? (base.fontSize ?? 14) * size : null,
    );
    return style == const TextStyle() ? null : style;
  }

  /// 从 css 文本中取单个属性的值(如 'font-size:1.35em' → '1.35em')
  static String? _matchCss(String? css, String prop) {
    if (css == null) return null;
    final m = RegExp('(?:^|;)\\s*$prop\\s*:\\s*([^;]+)').firstMatch(css);
    return m?.group(1)?.trim();
  }

  /// margin 解析:'12px 0 8px' → (上, 下);两值时为 (值, 值),单值同
  static (double, double) _parseMargin(String? value) {
    if (value == null) return (0, 0);
    final nums = [
      for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(value))
        double.parse(m.group(0)!),
    ];
    if (nums.isEmpty) return (0, 0);
    if (nums.length == 1) return (nums[0], nums[0]);
    return (nums[0], nums[2] < nums.length ? nums[2] : nums[1]);
  }

  /// 字号解析:'1.35em' → 1.35、'120%' → 1.2、'14px' → 14/基准
  static double _parseFontFactor(String? value) {
    if (value == null) return 1;
    if (value.endsWith('em')) {
      return double.tryParse(value.replaceAll('em', '')) ?? 1;
    }
    if (value.endsWith('%')) {
      return (double.tryParse(value.replaceAll('%', '')) ?? 100) / 100;
    }
    final px = double.tryParse(value.replaceAll('px', ''));
    return px == null ? 1 : px / 14;
  }

  /// 颜色解析:#hex / rgb(r,g,b) / 常见颜色名(bbcode [color=Red] 会产出颜色名)
  static Color? _parseColor(String? value) {
    if (value == null || value.isEmpty) return null;
    var v = value.trim().toLowerCase();
    if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      final n = int.tryParse(hex, radix: 16);
      if (n == null) return null;
      return Color(0xFF000000 | n);
    }
    final rgb = RegExp(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)')
        .firstMatch(v);
    if (rgb != null) {
      return Color.fromARGB(
        255,
        int.parse(rgb.group(1)!),
        int.parse(rgb.group(2)!),
        int.parse(rgb.group(3)!),
      );
    }
    const names = {
      'black': Colors.black,
      'white': Colors.white,
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'gray': Colors.grey,
      'grey': Colors.grey,
      'brown': Colors.brown,
      'pink': Colors.pink,
      'cyan': Colors.cyan,
      'lime': Colors.lime,
      'gold': Color(0xFFFFD700),
      'silver': Color(0xFFC0C0C0),
      'darkred': Color(0xFF8B0000),
      'darkblue': Color(0xFF00008B),
      'darkgreen': Color(0xFF006400),
    };
    return names[v];
  }

  /// 等宽样式:代码块/行内代码
  static TextStyle _monoStyle(ThemeData theme, TextStyle base) {
    return base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Consolas', 'Courier New'],
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }

  /// 块级间距包装
  static Widget _block(Widget child, {double top = 0, double bottom = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: child,
    );
  }
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

/// 文字表格列宽:按单元格内容自然宽度,单列最多 [cap] 逻辑像素。
///
/// 与 FlexColumnWidth 等分不同,多列表格每列按各自内容宽,
/// 内容过长(超过上限)时在列内换行;表格总宽超过容器时由
/// 横向滚动容器兜底
class _CappedIntrinsicColumnWidth extends TableColumnWidth {
  const _CappedIntrinsicColumnWidth(this.cap);

  final double cap;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      0;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var maxWidth = 0.0;
    for (final cell in cells) {
      final w = cell.getMaxIntrinsicWidth(double.infinity);
      if (w > maxWidth) maxWidth = w;
    }
    return maxWidth > cap ? cap : maxWidth;
  }

  @override
  double? flex(Iterable<RenderBox> cells) => null;
}

/// 合并单元格网格模型中的锚定格(rowspan/colspan 展开为占用区域)
class _GridCell {
  const _GridCell({
    required this.el,
    required this.row,
    required this.col,
    required this.rowSpan,
    required this.colSpan,
  });

  final dom.Element el;
  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;
}
