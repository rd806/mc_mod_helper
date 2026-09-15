import 'package:flutter/material.dart';

/// 解析十六进制 RGB 色号:#RGB / #RRGGBB,井号可省、大小写不限。
/// 非法输入返回 null(如何提示由调用方决定)。
Color? parseHexColor(String input) {
  var hex = input.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.isEmpty || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
  // #abc → #aabbcc
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// 颜色 → #RRGGBB(大写,便于比对与复制)
String formatHexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 点击弹出输入框的颜色设置项。
///
/// 行内显示当前颜色的圆形色块(旁边附色号,否则光看圆点认不出自己设的是什么),
/// 点击后在屏幕中间弹出对话框输入十六进制色号。与 [InputBox] 同一套交互
/// (见 input_box.dart),区别是这里要校验:色号非法时不关闭对话框,
/// 在输入框下方提示,并把能解析出来的输入实时画成预览圆点。
class ColorBox extends StatelessWidget {
  const ColorBox({
    super.key,
    required this.title,
    required this.value,
    required this.onSaved,
  });

  /// 设置项名称(行内标签,同时作为对话框标题)
  final String title;

  /// 当前颜色
  final Color value;

  /// 「确定」后回写(已校验为合法颜色;取消不改动)
  final ValueChanged<Color> onSaved;

  Future<void> _showColorDialog(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorDialog(title: title, initial: value),
    );
    if (picked != null) onSaved(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showColorDialog(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Row(
          children: [
            Text(title, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              formatHexColor(value),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            ColorDot(color: value),
          ],
        ),
      ),
    );
  }
}

/// 圆形色块(描一圈边框:白色/浅色不然在浅色背景上看不出形状)
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 28});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );
  }
}

/// 输入对话框:TextField 由 State 持有,随对话框一起释放
/// (在 showDialog 返回后立刻 dispose 会撞上退场动画期间的重建)
class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: formatHexColor(widget.initial),
  );

  /// 预览色:跟随可解析的输入变化,输入非法时保持上一次的预览(不闪)
  late Color _preview = widget.initial;

  /// 格式错误的提示。只在点过「确定」后出现 —— 边打字边报红太吵,
  /// 而输入过程中(#3F5 → #3F51B5)必然经过若干"非法"中间态
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final parsed = parseHexColor(text);
    if (parsed == null) return;
    setState(() {
      _preview = parsed;
      _error = null; // 改成合法值就把提示收掉
    });
  }

  void _submit() {
    final parsed = parseHexColor(_controller.text);
    if (parsed == null) {
      setState(() => _error = '请输入十六进制色号,如 #3F51B5');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          // 居中包一层:上面是 stretch,不包的话圆点会被拉成椭圆
          Center(child: ColorDot(color: _preview, size: 56)),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '#3F51B5',
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
