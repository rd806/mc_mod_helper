import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/render/html_content.dart';

/// 渲染被测 HTML(链接回调可捕获点击 url)
Widget _wrap(String html, [void Function(String url)? onLinkTap]) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HtmlContent(html: html, onLinkTap: onLinkTap ?? (_) {}),
      ),
    ),
  );
}

/// 找出一段 RichText 文本里与 [needle] 相关的最深层 TextSpan 样式
/// (沿继承链合并:子 span 样式叠加在父 span 之上)
TextStyle? _spanStyle(WidgetTester tester, String needle) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(needle),
    ),
  );
  TextStyle? style;
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is TextSpan) {
      final merged = span.style == null
          ? inherited
          : (inherited?.merge(span.style) ?? span.style);
      if (span.text?.contains(needle) ?? false) style = merged;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, merged);
      }
    }
  }

  walk(rich.text, rich.text.style);
  return style;
}

/// 限定在 HtmlContent 子树内的查找器
/// (整个页面里有路由 ModalBarrier 自带的 MouseRegion 等框架噪声)
Finder _inContent(Finder finder) =>
    find.descendant(of: find.byType(HtmlContent), matching: finder);

void main() {
  testWidgets('纯文字表格:Table 渲染、单线边框、表头加粗居中', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<table><tr><th>按键</th><th>功能</th></tr>'
        '<tr><td>F3</td><td>调试信息</td></tr></table>',
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    // TableBorder.all 天然是单线(相邻单元格各画一边会合并),无双线问题
    expect(tester.widget<Table>(find.byType(Table)).border, isNotNull);
    expect(find.textContaining('调试信息', findRichText: true), findsOneWidget);
    // 表头:居中 + 加粗
    final th = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '按键',
      ),
    );
    expect(th.textAlign, TextAlign.center);
    expect(_spanStyle(tester, '按键')?.fontWeight, FontWeight.bold);
  });

  testWidgets('多列文字表格:列宽按内容自然宽(不压窄),超宽横向滚动', (tester) async {
    // 6 列,每列内容约 140px,自然总宽远超 800 的测试视口:
    // 旧等分列宽会把每列压到 ~130px 以内,新实现保持自然宽并横向滚动
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<th>很长的列标题内容甲</th><th>很长的列标题内容乙</th>'
        '<th>很长的列标题内容丙</th><th>很长的列标题内容丁</th>'
        '<th>很长的列标题内容戊</th><th>很长的列标题内容己</th>'
        '</tr></table>',
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    // 文字表格包在横向滚动容器里
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView &&
            w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    // 关键回归:表格按内容自然宽布局,总宽超过视口(不被等分压窄)
    expect(
      tester.getSize(find.byType(Table)).width,
      greaterThan(800),
    );
  });

  testWidgets('rowspan 纵向合并单元格:JEI 物品列表样式渲染正确', (tester) async {
    // 真实结构:左侧 '物品列表' 单元格纵向合并 3 行,
    // 右侧各行分别是 物品列表/物品列表搜索/物品作弊
    await tester.pumpWidget(
      _wrap(
        '<table><tr><th>物品列表</th><th>功能</th></tr>'
        '<tr><td rowspan="3">物品列表</td><td>物品列表</td></tr>'
        '<tr><td>物品列表搜索</td></tr>'
        '<tr><td>物品作弊</td></tr></table>',
      ),
    );

    // 渲染无异常,合并格与各行内容都在
    expect(find.byType(Table), findsNothing); // 合并表格不走 Table 控件
    expect(find.textContaining('物品列表搜索', findRichText: true), findsOneWidget);
    expect(find.textContaining('物品作弊', findRichText: true), findsOneWidget);
    expect(find.textContaining('功能', findRichText: true), findsOneWidget);
    // 精确匹配 '物品列表' 出现 3 次:表头 + 纵向合并格 + 右侧第一行
    // (textContaining 会把 '物品列表搜索' 也算进去)
    expect(find.text('物品列表', findRichText: true), findsNWidgets(3));
  });

  testWidgets('colspan 横向合并单元格:横跨整行', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<table><tr><td colspan="2">横跨两列的内容</td></tr>'
        '<tr><td>甲</td><td>乙</td></tr></table>',
      ),
    );

    // 取文字最近的祖先 Container(即单元格边框盒)测量,
    // RichText 本身缩到文字宽度,不能反映单元格宽
    Finder cellOf(Finder text) =>
        find.ancestor(of: text, matching: find.byType(Container)).first;
    final merged = tester.getRect(
      cellOf(find.textContaining('横跨两列', findRichText: true)),
    );
    // 合并格宽 = 下一行两列宽度之和(证明横跨了两列,自然列宽布局)
    final a = tester.getRect(cellOf(find.text('甲', findRichText: true)));
    final b = tester.getRect(cellOf(find.text('乙', findRichText: true)));
    expect((merged.width - (a.width + b.width)).abs(), lessThan(4));
    // 左右边缘跨行对齐(证明列宽一致)
    expect(a.left - merged.left, lessThan(20));
    expect(merged.right - b.right, lessThan(20));
  });

  testWidgets('合并单元格表格:内容自然列宽,超宽横向滚动', (tester) async {
    // 4 列 rowspan 表,长标题使每列达到 240 上限,总宽约 960 > 800 视口
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<th>这是一个非常长的功能列标题说明文字内容甲</th>'
        '<th>这是一个非常长的功能列标题说明文字内容乙</th>'
        '<th>这是一个非常长的功能列标题说明文字内容丙</th>'
        '<th>这是一个非常长的功能列标题说明文字内容丁</th>'
        '</tr><tr>'
        '<td rowspan="2">物品列表</td><td>搜索</td><td>作弊</td><td>设置</td>'
        '</tr><tr><td>快捷键设置</td><td>其他功能</td><td>辅助说明</td></tr>'
        '</table>',
      ),
    );

    // 合并表格也包在横向滚动容器里
    final scsv = tester.widget<SingleChildScrollView>(
      find
          .byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          )
          .first,
    );
    // 关键回归:表格按内容自然宽布局,总宽超过视口(不被压窄)
    expect(tester.getSize(find.byWidget(scsv.child!)).width, greaterThan(800));
    // 合并格与各行内容渲染正常
    expect(find.textContaining('物品列表搜索', findRichText: true), findsNothing);
    expect(find.textContaining('快捷键设置', findRichText: true), findsOneWidget);
    expect(find.textContaining('辅助说明', findRichText: true), findsOneWidget);
  });

  testWidgets('含行内头像图片的表格:固有宽度测量不触发框架断言', (tester) async {
    // 真实案例:Modrinth 贡献者表格(anvilcraft 等),单元格内是
    // 100px 头像 + 名字。行内图片宽度必须有界——无限宽(含加载中/
    // 失败占位)会让表格固有宽度测量触发 TextPainter
    // 'maxIntrinsicLineExtent.isFinite' 断言
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<td align="center"><a href="https://github.com/XeKr">'
        '<img src="https://avatars.githubusercontent.com/u/1?v=100" '
        'width="100px" height="100px" alt=""/><br/>'
        '<sub><b>XeKr</b></sub></a></td>'
        '<td align="center"><img src="https://avatars.githubusercontent.com/u/2?v=100" '
        'width="100px" height="100px"/><br/>成员乙</td>'
        '</tr><tr>'
        '<td align="center"><img src="https://avatars.githubusercontent.com/u/3?v=100" '
        'width="100px" height="100px"/><br/>成员丙</td>'
        '<td align="center"><img src="https://avatars.githubusercontent.com/u/4?v=100" '
        'width="100px" height="100px"/><br/>成员丁</td>'
        '</tr></table>',
      ),
    );
    // 测试环境图片请求失败 → errorBuilder 占位(旧实现为无限宽,此处必崩)
    await tester.pump();
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('XeKr', findRichText: true), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
  });

  testWidgets('图注格:图片+图下说明,图片可点灯箱', (tester) async {
    // 真实结构:mcmod 画廊「更多展示」里部分单元格是
    // <a><img></a><br>说明文字,此前因文本非空被当普通文字格,
    // 图片走行内渲染而无法点击预览
    String? tapped;
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<td><a href="https://x/1.png"><img src="https://x/1.png"></a>'
        '<br>说明文字甲</td>'
        '<td><a href="https://x/2.png"><img src="https://x/2.png"></a></td>'
        '</tr></table>',
        (u) => tapped = u,
      ),
    );
    await tester.pump(); // 图片网络失败 → errorBuilder 占位

    // 画廊判定:含图注格的表格等宽列(框线与文字表格一致)
    expect(tester.widget<Table>(find.byType(Table)).border, isNotNull);
    // 图注图片固定 180 高(占位),说明文字渲染在下方
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 180),
      findsNWidgets(2),
    );
    expect(find.textContaining('说明文字甲', findRichText: true), findsOneWidget);
    // 点击图注图片 → 灯箱分流回调收到图片地址
    await tester.tap(find.byType(Image).first);
    expect(tapped, 'https://x/1.png');
  });

  testWidgets('图注格(figcaption 结构):mcmod 更多展示的图片+图注,图片可点灯箱', (tester) async {
    // 真实结构(机械动力 更多展示):
    // <td><span class="figure"><a><img></a><span class="figcaption">脉冲延长器</span></span></td>
    // 图注文字是 figcaption 标签,与图片同包在 span.figure 里,
    // 没有块级换行分隔——必须有 figcaption 判定信号
    String? tapped;
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<td><span class="figure">'
        '<a href="https://x/1.png"><img src="https://x/1.png"></a>'
        '<span class="figcaption">脉冲延长器</span></span></td>'
        '<td><span class="figure">'
        '<a href="https://x/2.png"><img src="https://x/2.png"></a>'
        '<span class="figcaption">流水线压板</span></span></td>'
        '</tr></table>',
        (u) => tapped = u,
      ),
    );
    await tester.pump(); // 图片网络失败 → errorBuilder 占位

    // 画廊判定:等宽列(框线与文字表格一致)
    expect(tester.widget<Table>(find.byType(Table)).border, isNotNull);
    // 图注文字渲染
    expect(find.text('脉冲延长器'), findsOneWidget);
    expect(find.text('流水线压板'), findsOneWidget);
    // 点击图注图片 → 灯箱分流回调收到图片地址
    await tester.tap(find.byType(Image).first);
    expect(tapped, 'https://x/1.png');
  });

  testWidgets('JEI 同行混排格:图标+物品名保持行内渲染,不误判为图注', (tester) async {
    // <a><img></a>物品名:物品名与图片同行,必须保持行内混排
    // (不被图注判定夺走,不出现 180 高的块级图片)
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<td><a href="https://x/icon.png"><img src="https://x/icon.png"></a>'
        '物品名甲</td>'
        '<td><a href="https://x/icon2.png"><img src="https://x/icon2.png"></a>'
        '物品名乙</td>'
        '</tr></table>',
      ),
    );
    await tester.pump();

    expect(find.textContaining('物品名甲', findRichText: true), findsOneWidget);
    expect(find.textContaining('物品名乙', findRichText: true), findsOneWidget);
    // 行内图标自然尺寸:不出现图注/画廊的 180 高块级图片
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 180),
      findsNothing,
    );
    // 文字表格:有框线
    expect(tester.widget<Table>(find.byType(Table)).border, isNotNull);
  });

  testWidgets('画廊表格:图片固定高度 180、单线框线', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<table><tr>'
        '<td><a href="https://x/1.png"><img src="https://x/1.png"></a></td>'
        '<td><a href="https://x/2.png"><img src="https://x/2.png"></a></td>'
        '</tr></table>',
      ),
    );
    await tester.pump(); // 图片网络请求失败 → errorBuilder 占位

    expect(find.byType(Table), findsOneWidget);
    // 画廊与文字表格统一框线
    expect(tester.widget<Table>(find.byType(Table)).border, isNotNull);
    // 图片加载失败也保持固定高度占位(测试环境网络 400,走 errorBuilder)
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 180),
      findsWidgets,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(2));
  });

  testWidgets('正文链接/图片/表格均不产生 MouseRegion(fwfh 断言根源回归)', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<p>文字 <a href="https://www.mcmod.cn/class/36.html">OptiFine</a> '
        '<strong>加粗</strong> <span style="color:#ff0000">红色</span></p>'
        '<table><tr><td><a href="https://x/1.png"><img src="https://x/1.png">'
        '</a></td></tr></table>'
        '<p><a href="https://x/2.png"><img src="https://x/2.png"></a></p>',
      ),
    );
    await tester.pump();

    // 核心回归:正文子树里没有任何 MouseRegion
    expect(_inContent(find.byType(MouseRegion)), findsNothing);
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('文字链接点击回调 url', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      _wrap('<p>点击 <a href="https://a.b/c">这里</a> 跳转</p>', (u) => tapped = u),
    );

    // 用 textRange 定位链接文本 '这' 字的位置,换算成全局坐标点击
    // (点 RichText 中心会落在空格上,空格属于父 span,不带识别器)
    final rich = find.textContaining('点击', findRichText: true);
    final local = tester
        .renderObject<RenderParagraph>(rich)
        .getBoxesForSelection(TextSelection(baseOffset: 3, extentOffset: 4))
        .single
        .toRect()
        .center; // 局部坐标,需加上 RichText 的全局左上角
    await tester.tapAt(tester.getTopLeft(rich) + local);
    expect(tapped, 'https://a.b/c');
  });

  testWidgets('正文图片点击回调图片地址(灯箱分流在调用方)', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      _wrap(
        '<p><a href="https://x/1.png"><img src="https://x/1.png"></a></p>',
        (u) => tapped = u,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(Image));
    expect(tapped, 'https://x/1.png');
  });

  testWidgets('行内样式:span 颜色名/hex、strong 加粗、em 斜体', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<p><span style="color:Red">红色文字</span> '
        '<span style="color:#00ff00">绿色文字</span> '
        '<strong>加粗</strong> <em>斜体</em></p>',
      ),
    );

    expect(_spanStyle(tester, '红色文字')?.color, Colors.red);
    expect(_spanStyle(tester, '绿色文字')?.color, const Color(0xFF00FF00));
    expect(_spanStyle(tester, '加粗')?.fontWeight, FontWeight.bold);
    expect(_spanStyle(tester, '斜体')?.fontStyle, FontStyle.italic);
  });

  testWidgets('标题按级别放大加粗,列表带序号与缩进', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<h2>二级标题</h2>'
        '<ul><li>无序一</li><li>无序二</li></ul>'
        '<ol><li>有序一</li><li>有序二</li></ol>',
      ),
    );

    final h2 = _spanStyle(tester, '二级标题');
    expect(h2?.fontWeight, FontWeight.bold);
    expect(h2?.fontSize, greaterThan(14)); // bodyMedium 默认 14,1.35 倍放大
    expect(find.text('•', findRichText: true), findsNWidgets(2));
    expect(find.text('1.', findRichText: true), findsOneWidget);
    expect(find.text('2.', findRichText: true), findsOneWidget);
  });

  testWidgets('剧透 details 折叠,点击展开', (tester) async {
    await tester.pumpWidget(
      _wrap('<details><summary>剧透内容</summary>秘密信息</details>'),
    );

    expect(find.text('剧透内容'), findsOneWidget);
    expect(find.text('秘密信息', findRichText: true), findsNothing);

    await tester.tap(find.text('剧透内容'));
    await tester.pump();
    expect(find.text('秘密信息', findRichText: true), findsOneWidget);
  });

  testWidgets('模拟 mcmod 清洗后的真实正文片段完整渲染无异常', (tester) async {
    // 结构参照真实详情页:样式标题(bbcode 转来)、懒加载已换 src 的图片、
    // javascript 弹窗链接已转 span、站内 class 链接、图片画廊表格
    await tester.pumpWidget(
      _wrap(
        '<span style="font-weight:bold;font-size:1.35em">模组介绍</span>'
        '<p style="box-sizing: border-box; margin:12px 0 8px">正文文字,'
        '访问<a href="https://www.mcmod.cn/class/36.html">OptiFine</a>。</p>'
        '<p><a href="https://i.mcmod.cn/a.webp"><img src="https://i.mcmod.cn/a.webp"></a></p>'
        '<table><tr><td><a href="https://i.mcmod.cn/1.webp">'
        '<img src="https://i.mcmod.cn/1.webp"></a></td>'
        '<td><a href="https://i.mcmod.cn/2.webp">'
        '<img src="https://i.mcmod.cn/2.webp"></a></td></tr></table>'
        '<ul style="list-style-type: disc;"><li>特性一</li><li>特性二</li></ul>',
      ),
    );
    await tester.pump();

    expect(find.text('模组介绍', findRichText: true), findsOneWidget);
    expect(find.textContaining('OptiFine', findRichText: true), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('•', findRichText: true), findsNWidgets(2));
    expect(_inContent(find.byType(MouseRegion)), findsNothing);
  });
}
