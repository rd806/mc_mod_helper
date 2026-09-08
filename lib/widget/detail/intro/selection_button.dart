import 'package:flutter/material.dart';

/// 分段切换按钮(详情页窄屏「介绍/信息」切换器)。
///
/// 选中项由父组件通过 [selectedIndex] 驱动:高亮滑块用
/// AnimatedPositioned 跟随选中按钮滑动。滑块目标存在 State 里,
/// 选中变化在 didUpdateWidget 中同步重测——此时按钮已完成布局
/// (按钮位置与选中无关),随后必然发生的 build 让 AnimatedPositioned
/// 从旧位置隐式动画到新位置;首次构建(按钮未布局)用帧后回调定位。
class SelectionButton extends StatefulWidget {
  const SelectionButton({
    super.key,
    required this.button,
    required this.selectedIndex,
    required this.switchTo,
  });

  /// 分段定义:(标签, 选中值)
  final List<(String, int)> button;

  /// 当前选中值(与 button 的 $2 比较,决定滑块位置与文字高亮)
  final int selectedIndex;

  /// 切换回调(由父组件更新选中值)
  final void Function(int index) switchTo;

  /// 组件总高(含 Card 外边距),按当前主题字号精确计算。
  ///
  /// 吸顶用的 SliverPersistentHeader 需要数值型 extent,高度写死会造成
  /// 组件被拉高悬浮(空带)或放不下被裁剪;统一由本方法给出与 build
  /// 结果一致的高度,委托用它与 min/maxExtent 对齐
  static double preferredHeight(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    final scaler = MediaQuery.textScalerOf(context);
    // 文字行高(字号 × 行高系数,再乘系统/应用字体缩放)
    final textH = (style?.height ?? 1.4) * scaler.scale(style?.fontSize ?? 16);
    // 按钮高 = max(M3 最小高 40, 文字 + 上下内边距 5*2)
    final btnH = textH + 10 > 40 ? textH + 10 : 40;
    // Card 内边距 4*2 + Card 外边距 4*2
    return btnH + 16;
  }

  @override
  State<SelectionButton> createState() => _SelectionButtonState();
}

class _SelectionButtonState extends State<SelectionButton> {
  final List<GlobalKey> _buttonKeys = [];
  final GlobalKey _stackKey = GlobalKey();

  /// 高亮滑块目标(相对 Stack);按钮未布局前为 null,不显示滑块
  Rect? _target;

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
    // 首帧布局完成后定位初始高亮(此时按钮刚完成布局)
    WidgetsBinding.instance.addPostFrameCallback((_) => _setTarget());
  }

  @override
  void didUpdateWidget(SelectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.button.length != oldWidget.button.length) {
      // 分段增删:按键重建,布局未完成,帧后重新定位
      _rebuildKeys();
      WidgetsBinding.instance.addPostFrameCallback((_) => _setTarget());
      return;
    }
    // 选中变化:按钮位置与选中无关、当前布局已就绪,
    // 同步重测目标,随后的 build 让滑块从旧位置滑过来
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _target = _measure();
    }
  }

  void _rebuildKeys() {
    _buttonKeys
      ..clear()
      ..addAll(List.generate(widget.button.length, (_) => GlobalKey()));
  }

  /// 选中值对应的分段下标;无匹配返回 null(不显示滑块)
  int? _indexOf(int value) {
    for (var i = 0; i < widget.button.length; i++) {
      if (widget.button[i].$2 == value) return i;
    }
    return null;
  }

  /// 帧后/重建后定位滑块:重新测量并触发重建
  void _setTarget() {
    if (!mounted) return;
    setState(() => _target = _measure());
  }

  /// 选中按钮相对 Stack 内容区的边界;按钮尚未布局时返回 null
  Rect? _measure() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final i = _indexOf(widget.selectedIndex);
    if (i == null || stackBox == null || !stackBox.hasSize) return null;
    final box = _buttonKeys[i].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(stackBox),
      Offset.zero & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        // 显式固定外边距(M3 默认随版本变化,公式按 4 计算)
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            key: _stackKey,
            children: [
              // 高亮滑块:铺在按钮行下层,随选中滑动(Row 决定 Stack 尺寸)
              if (_target != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: _target!.left,
                  top: _target!.top,
                  width: _target!.width,
                  height: _target!.height,
                  child: _buildHighlight(theme),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildButtons(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建按钮列表
  List<Widget> _buildButtons(ThemeData theme) {
    return [
      for (var i = 0; i < widget.button.length; i++) _buildButton(theme, i),
    ];
  }

  /// 构建单个按钮
  Widget _buildButton(ThemeData theme, int i) {
    final (label, value) = widget.button[i];
    return TextButton(
      key: _buttonKeys[i],
      style: TextButton.styleFrom(
        backgroundColor: Colors.transparent,
        // 锁死按钮尺寸与 padding:高度 = max(40, 文字 + child 垂直 padding),
        // 与 preferredHeight 计算一致(M3 默认 padded tap target 会叠到 48,
        // 必须 shrinkWrap + 显式 minimumSize 才能让实际高等于公式)
        minimumSize: const Size(64, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: () => widget.switchTo(value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// 构建高亮框
  Widget _buildHighlight(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
