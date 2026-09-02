import 'package:flutter/material.dart';

class HyperRender {

  /// hyper_render 的主题适配:包默认正文样式是 16px 深灰字,用 customCss
  /// 注入正文颜色/字号/字体(字体缩放走 MediaQuery,包默认读取)。
  /// 颜色取 bodyMedium 的常规字体颜色(与普通 Text 控件一致),
  /// 不使用 colorScheme 主题色。
  /// 注意:UDT 树根节点 tagName 是 'document'(HTML/Markdown 均是),
  /// 用 'body' 选择器匹配不到任何节点;注入根节点后靠继承传播到正文,
  /// 行内 style 优先级更高,正文里的颜色文字不受影响
  static String hyperCss(ThemeData theme) {
    final textStyle = theme.textTheme.bodyMedium;
    final color = (textStyle?.color ?? theme.colorScheme.onSurface).toARGB32();
    final hex = color.toRadixString(16).padLeft(8, '0').substring(2);
    final family = textStyle?.fontFamily;
    // 包内 CSS 解析器把 font-family 整值去引号后当作单个家族名,
    // 不支持逗号分隔的回退列表;取 bodyMedium 的家族名(应用字体)
    final familyCss =
    (family == null || family.isEmpty) ? '' : 'font-family: $family; ';
    return 'document { color: #$hex; '
        'font-size: ${textStyle?.fontSize ?? 14}px; '
        '$familyCss}';
  }
}