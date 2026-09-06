part of '../html_content.dart';

// ---------- 合并单元格网格 ----------

/// 含合并单元格(rowspan/colspan)的表格:Flutter 的 Table 不支持,
/// 改用「IntrinsicHeight(Row) + 定宽单元格」网格模型渲染。
///
/// - 列宽:每列按内容自然宽(文本用 TextPainter 实测、图片取属性宽,
///   横向合并格的内容宽按列数均摊),单列上限 240px——与文字表格
///   路径一致,多列表格列宽不被压窄;画廊(含图片的表格)则每列
///   固定为缩略图宽度,与 Table 路径一致;
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
  void Function(String) onLinkTap,
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
        _GridCell(el: cell, row: r, col: c, rowSpan: rowSpan, colSpan: colSpan),
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

  // 画廊:每列固定为缩略图宽度(与 Table 路径一致,不做内容测量)
  final colWidth = isGallery
      ? List<double>.filled(colCount, _galleryImageWidth)
      : List.generate(colCount, (c) {
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
        child: _cellContent(
          context,
          theme,
          base,
          cell.el,
          isGallery,
          onLinkTap,
        ),
      ),
    );
  }

  Widget placeholder(_GridCell anchor, int r) {
    final isLastRow = anchor.row + anchor.rowSpan - 1 == r;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: side, bottom: isLastRow ? side : BorderSide.none),
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
