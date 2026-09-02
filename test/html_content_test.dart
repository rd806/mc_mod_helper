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

  testWidgets('画廊表格:图片固定高度 180、无框线', (tester) async {
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
    // 画廊无框线
    expect(tester.widget<Table>(find.byType(Table)).border, isNull);
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
