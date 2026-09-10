part of '../html_content.dart';

// ---------- 样式解析 ----------

/// 解析 '100px'/'100px;' 形式的宽高属性为数值,非法返回 null
double? _attrPx(String? value) {
  if (value == null) return null;
  final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
  return m == null ? null : double.parse(m.group(0)!);
}

/// 块级 style 解析:text-align、margin(px)、font-size(em/%)、font-weight
({
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
TextStyle? _parseInlineStyle(String? css, TextStyle base) {
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
String? _matchCss(String? css, String prop) {
  if (css == null) return null;
  final m = RegExp('(?:^|;)\\s*$prop\\s*:\\s*([^;]+)').firstMatch(css);
  return m?.group(1)?.trim();
}

/// margin 解析:'12px 0 8px' → (上, 下);两值时为 (值, 值),单值同
(double, double) _parseMargin(String? value) {
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
double _parseFontFactor(String? value) {
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
Color? _parseColor(String? value) {
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
TextStyle _monoStyle(ThemeData theme, TextStyle base) {
  return base.copyWith(
    fontFamily: 'Consolas',
    // Microsoft YaHei 保证中文字体正常显示
    fontFamilyFallback: const ['monospace', 'Courier New', 'Microsoft YaHei'],
    backgroundColor: theme.colorScheme.surfaceContainerHighest,
  );
}
