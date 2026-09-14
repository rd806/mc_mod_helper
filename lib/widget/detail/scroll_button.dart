import 'package:flutter/material.dart';

/// 返回顶部按钮
/// 用户下滚隐藏，上滚显示
class ScrollToTopButton extends StatefulWidget {
  /// 控制器
  final ScrollController controller;
  final double threshold;
  final Duration animationDuration;
  final EdgeInsets padding;
  final Widget? customButton;
  final VoidCallback? onPressed;
  final Duration fadeDuration;

  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold = 200,
    this.animationDuration = const Duration(milliseconds: 1000),
    this.padding = const EdgeInsets.only(bottom: 30, right: 20),
    this.customButton,
    this.onPressed,
    this.fadeDuration = const Duration(milliseconds: 200),
  });

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _showButton = false;
  double _lastOffset = 0;
  bool _animatingToTop = false;
  late ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 桌面端窗口在宽/窄布局间切换时,父层换绑了 controller
    // (窄屏整页滚动 vs 宽屏左栏)。initState 只绑了最初的 controller,
    // 不在此处重绑会导致按钮盯着已无滚动位置/不再可滚的旧 controller,
    // 出现不显示或误触发。切换后立即按新 controller 当前偏移同步显隐。
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onScroll);
      _controller = widget.controller;
      _controller.addListener(_onScroll);
      _lastOffset = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncToOffset();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    super.dispose();
  }

  /// 按当前偏移同步显隐(用于换绑 controller 后无滚动事件也能正确显示)
  void _syncToOffset() {
    if (!_controller.hasClients) return;
    final off = _controller.offset;
    _lastOffset = off;
    final shouldShow = off > widget.threshold;
    if (shouldShow != _showButton) {
      setState(() => _showButton = shouldShow);
    }
  }

  /// 滚动事件处理
  void _onScroll() {
    if (!_controller.hasClients) return;
    final offset = _controller.offset;
    final increasing = offset > _lastOffset;
    _lastOffset = offset;
    // 返回顶部的动画本身会让 offset 减小,期间不再改显隐
    if (_animatingToTop) return;

    var shouldShow = _showButton;
    if (increasing) {
      // 往上滚(内容向尾部):隐藏,给阅读让位
      shouldShow = false;
    } else if (offset < widget.threshold) {
      // 已经很接近顶部:隐藏
      shouldShow = false;
    } else {
      // 往下滚(回顶部方向)且离开顶部足够远:显示
      shouldShow = true;
    }
    if (shouldShow != _showButton) {
      setState(() => _showButton = shouldShow);
    }
  }

  /// 返回顶部
  Future<void> _scrollToTop() async {
    _animatingToTop = true;
    try {
      await widget.controller.animateTo(
        0,
        duration: widget.animationDuration,
        curve: Curves.easeInOut,
      );
    } finally {
      _animatingToTop = false;
      // 回到顶部后隐藏
      _lastOffset = 0;
      if (_showButton) setState(() => _showButton = false);
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      bottom: widget.padding.bottom,
      right: widget.padding.right,
      // child 常驻:显隐都用 AnimatedOpacity 在 0↔1 间淡入/淡出
      // (把隐藏分支换成 SizedBox 会导致直接消失,没有淡出动画);
      // 隐藏时由 IgnorePointer 屏蔽点击,淡出过程中不可再点
      child: IgnorePointer(
        ignoring: !_showButton,
        child: AnimatedOpacity(
          opacity: _showButton ? 1.0 : 0.0,
          duration: widget.fadeDuration,
          curve: Curves.easeInOut,
          child: GestureDetector(
            onTap: _scrollToTop,
            child: widget.customButton ?? _buildScrollButton(theme),
          ),
        ),
      ),
    );
  }

  /// 滚动按钮
  Widget _buildScrollButton(ThemeData theme) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.arrow_upward, size: 28),
    );
  }
}
