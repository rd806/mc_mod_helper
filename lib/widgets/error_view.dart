import 'package:flutter/material.dart';

/// 加载失败提示 + 重试
class ErrorView extends StatelessWidget {
    const ErrorView({super.key, required this.message, required this.onRetry});

    final String message;
    final VoidCallback onRetry;

    @override
    Widget build(BuildContext context) {
        return Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('加载失败\n$message', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
            ),
        ),
        );
    }
}
