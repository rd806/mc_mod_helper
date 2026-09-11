import 'package:flutter/material.dart';

/// 点击弹出输入框的设置项(单值文本配置)。
///
/// 平时行内只展示当前值,点击后在屏幕中间弹出对话框输入,
/// 「确定」才写回(取消不改动)。适合接口地址 / API Key / 模型名这类
/// 一行放不下、又不想在设置页里塞满输入框的配置。
class InputBox extends StatelessWidget {
  const InputBox({
    super.key,
    required this.title,
    required this.value,
    required this.hint,
    required this.onSaved,
    this.obscure = false,
  });

  /// 设置项名称(行内标签,同时作为对话框标题)
  final String title;

  /// 当前值(行内展示,并作为对话框的初始内容)
  final String value;

  /// 值为空时的占位提示(也作为对话框输入框的 hintText)
  final String hint;

  /// 是否遮蔽(API Key 这类敏感值:行内与输入框都以圆点显示)
  final bool obscure;

  /// 「确定」后回写;传空串表示清空(是否回落到默认由调用方决定)
  final ValueChanged<String> onSaved;

  Future<void> _showInputBox(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: title,
        initialValue: value,
        hint: hint,
        obscure: obscure,
      ),
    );
    if (result != null) onSaved(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 未配置时展示占位提示(灰色),已配置的敏感值只显示圆点
    final display = value.isEmpty
        ? hint
        : (obscure ? '•' * value.length.clamp(6, 16) : value);
    return InkWell(
      onTap: () => _showInputBox(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Row(
          children: [
            Text(title, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: value.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入对话框:TextField 由 State 持有,随对话框一起释放
/// (在 showDialog 返回后立刻 dispose 会撞上退场动画期间的重建)
class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.initialValue,
    required this.hint,
    required this.obscure,
  });

  final String title;
  final String initialValue;
  final String hint;
  final bool obscure;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  /// 敏感值默认遮蔽,可点右侧眼睛临时查看
  late bool _obscured = widget.obscure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscured,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _obscured ? '显示' : '隐藏',
                  icon: Icon(
                    _obscured ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
        ),
      ),
      actions: [
        TextButton(
          // 取消返回 null(与"确定清空"返回的空串区分开)
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
