part of '../html_content.dart';

// ---------- 表格 ----------

/// 表格:原生 Table 渲染。
///
/// - 纯文字表格:TableBorder.all 单线框线,表头加粗居中;
/// - 画廊(含图片的表格):每图按固定缩略图宽度(320×180)渲染,
///   图片固定高度,加载完成前就占据固定行高,不引起纵向布局移动;
///   整表随列数自然变宽,超出容器时横向滚动,图片不被压窄;
/// - 横向滚动容器(文字表格/画廊)桌面端支持鼠标拖拽。
/// colspan/rowspan 不支持(与 fwfh 行为一致,单元格按顺序渲染)。
Widget _buildTable(
  BuildContext context,
  ThemeData theme,
  TextStyle base,
  dom.Element el,
  void Function(String) onLinkTap,
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
  // 画廊判定:表格含任意图片。
  // 「截图欣赏」(纯图)、「更多展示」(图注)、JEI 物品表(混排/文字列)
  // 统一按固定缩略图宽度渲染,整表随列数自然变宽,
  // 超出容器时横向滚动,图片不被等分列压窄
  final isGallery = rows.any(
    (r) => r.any((c) => c.querySelector('img') != null),
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
    return _buildSpanGrid(
      context,
      theme,
      base,
      rows,
      colCount,
      isGallery,
      onLinkTap,
    );
  }
  final table = Table(
    columnWidths: isGallery
        // 画廊:每列固定为缩略图宽度,总宽 = 列数 × 320
        ? {
            for (var i = 0; i < colCount; i++)
              i: const FixedColumnWidth(_galleryImageWidth),
          }
        // 文字表格:每列按内容自然宽度(上限 240px,过长才在列内换行)。
        // 多列表格列宽不再被等分压窄
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
                _buildCell(context, theme, base, row[i], isGallery, onLinkTap)
              else
                const TableCell(child: SizedBox()),
          ],
        ),
    ],
  );
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    // 所有表格:总宽超过容器时横向滚动(桌面端支持鼠标拖拽)
    child: _wrapTableScroll(context, table),
  );
}

/// 表格的横向滚动容器:表格总宽超过容器时左右滚动,
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
  void Function(String) onLinkTap,
) {
  return TableCell(
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: _cellContent(context, theme, base, cell, isGallery, onLinkTap),
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
  void Function(String) onLinkTap,
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
        ..._captionBlocks(context, theme, base, cell, onLinkTap),
      ],
    );
  }
  if (cell.children.whereType<dom.Element>().any(_isBlockTag)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildBlocks(context, theme, base, cell.nodes, 0, onLinkTap),
    );
  }
  if (cell.localName == 'th') {
    return Text.rich(
      TextSpan(
        style: base.copyWith(fontWeight: FontWeight.bold),
        children: _buildInline(context, theme, base, cell.nodes, onLinkTap),
      ),
      textAlign: TextAlign.center,
    );
  }
  return Text.rich(
    TextSpan(
      style: base,
      children: _buildInline(context, theme, base, cell.nodes, onLinkTap),
    ),
  );
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
