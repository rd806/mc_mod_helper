import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

/// hyper_render 的主题适配回归:
/// 详情页用 'document { color; font-size }' 注入正文样式,
/// 这里锁住「根节点命中 → 子节点继承 → 行内样式优先」的级联行为
/// (包默认正文是 16px 深灰字,且 'body' 选择器在 UDT 树里匹配不到)。
void main() {
  test('document 选择器注入颜色/字号并继承,行内颜色优先', () {
    final doc = DocumentNode(
      children: [
        BlockNode(tagName: 'p', children: [TextNode('普通正文')]),
        BlockNode(
          tagName: 'p',
          attributes: {'style': 'color:#ff0000'},
          children: [TextNode('红色文字')],
        ),
      ],
    );

    final resolver = StyleResolver();
    resolver.parseCss(
      "document { color: #123456; font-size: 13px; font-family: 'NotoSansSC'; }",
    );
    resolver.resolveStyles(doc);

    // 根节点命中规则
    expect(doc.style.color, const Color(0xFF123456));
    expect(doc.style.fontSize, 13);
    expect(doc.style.fontFamily, 'NotoSansSC');
    // 未显式设置的子节点继承根节点样式
    final plain = doc.children[0];
    expect(plain.style.color, const Color(0xFF123456));
    expect(plain.style.fontSize, 13);
    expect(plain.style.fontFamily, 'NotoSansSC');
    // 行内 style 优先级高于规则,不被继承覆盖
    expect(doc.children[1].style.color, const Color(0xFFFF0000));
  });

  testWidgets('表格默认横向滚动,百分比宽度表格走 fitWidth(不滚动)', (tester) async {
    // 外层不用滚动容器,find.byType(SingleChildScrollView) 只统计表格包装
    Widget wrap(String table) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: HyperViewer(
            html: '<p>前文</p>$table',
            mode: HyperRenderMode.sync,
            shrinkWrap: true,
            selectable: false,
          ),
        ),
      ),
    );

    // 无百分比宽度:引擎默认 TableStrategy.horizontalScroll,包横向滚动容器
    await tester.pumpWidget(
      wrap(
        '<table><tr><th>很长的列名A</th><th>很长的列名B</th></tr>'
        '<tr><td>内容A</td><td>内容B</td></tr></table>',
      ),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );

    // style="width:100%":fitWidth 策略直接钳制宽度,不包滚动容器
    // (mcmod 清洗会把文字表格的百分比宽度剥掉,恢复横向滚动)
    await tester.pumpWidget(
      wrap(
        '<table style="width:100%"><tr><th>很长的列名A</th><th>很长的列名B</th></tr>'
        '<tr><td>内容A</td><td>内容B</td></tr></table>',
      ),
    );
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
