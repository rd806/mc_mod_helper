import 'package:flutter/material.dart';
import 'package:mc_mod_helper/api/mcmod.dart';

/// 处理安全验证:弹窗让用户看图输入验证码并提交。
///
/// 答案错误时服务器会返回新的挑战(新验证码图片),循环弹窗直到
/// 通过或用户取消。通过返回 true(调用方重试原请求),取消返回 false。
Future<bool> resolveCaptcha(
  BuildContext context,
  McmodCaptchaChallenge challenge,
) async {
  var current = challenge;
  while (true) {
    // 提交/弹窗之间页面可能已销毁(用户返回上一页)
    if (!context.mounted) return false;
    final answer = await showCaptchaDialog(context, current);
    if (answer == null) return false;
    final next = await McmodApi.submitCaptcha(current, answer);
    if (next == null) return true; // 验证通过
    current = next; // 答案错误:换图重来
  }
}

/// 站点安全验证对话框:验证码图片 + 问题 + 数字输入框
Future<String?> showCaptchaDialog(
  BuildContext context,
  McmodCaptchaChallenge challenge,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CaptchaDialog(challenge: challenge),
  );
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({required this.challenge});

  final McmodCaptchaChallenge challenge;

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('安全验证'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.challenge.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // 验证码图片(挑战页内嵌的 PNG 字节)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                widget.challenge.imageBytes,
                width: 240,
                height: 100,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_submitting,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '输入答案',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '验证中…' : '验证并继续'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    setState(() => _submitting = true);
    // 提交由 resolveCaptcha 完成,这里只把答案带回
    if (mounted) Navigator.of(context).pop(answer);
  }
}
