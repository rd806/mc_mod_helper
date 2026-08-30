import 'package:flutter/material.dart';

/// 灯箱:全屏暗底放大查看图片,点击任意处或关闭按钮退出,支持缩放
void showImageBox(BuildContext context, String url) {
    showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        barrierLabel: 'Image Box',
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) => _ImageBox(url: url),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
    );
}

/// 灯箱主体:全屏图片 + 点击任意处关闭 + 缩放
class _ImageBox extends StatelessWidget {
    const _ImageBox({required this.url});

    final String url;

    @override
    Widget build(BuildContext context) {
        return Stack(
            children: [
                Positioned.fill(
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: InteractiveViewer(
                            maxScale: 5,
                            child: Center(child: _buildImage()),
                        ),
                    ),
                ),
                Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                    ),
                ),
            ],
        );
    }

    // 处理图片
    Widget _buildImage() {
        return Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null ? child
                : const CircularProgressIndicator(color: Colors.white54),
            // 错误处理
            errorBuilder: (context, error, stackTrace) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    SizedBox(height: 8),
                    Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white54),
                    ),
                ],
            ),
        );
    }
}
