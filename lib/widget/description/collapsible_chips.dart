import 'package:flutter/material.dart';

/// 可折叠 chips 块（版本/相关链接共用）:
/// 超过两行时折叠显示，点击「展开全部」展开、再点收起。
///
/// 首帧渲染不可见的测量层（与显示层同宽完整布局、不占高度）,
/// post-frame 实测整块与单个 chip 高度判断是否超过两行，下一帧
/// 才展示折叠后的内容——呈现给用户的第一帧就是折叠态，无展开闪烁。
class CollapsibleChips extends StatefulWidget {
  const CollapsibleChips({super.key, required this.chips});

  final List<Widget> chips;

  @override
  State<CollapsibleChips> createState() => _CollapsibleChipsState();
}

class _CollapsibleChipsState extends State<CollapsibleChips> {
  final GlobalKey _wrapKey = GlobalKey();
  final GlobalKey _chipKey = GlobalKey();

  bool _expanded = false;

  /// 测量完成后才显示内容
  bool _measured = false;
  bool _overflow = false;

  /// 两行 chips 的高度(2 个 chip 高 + 1 个行距)
  double _twoLineHeight = 0;

  /// 测量时的布局宽度与字号倍率,变化时重新测量
  double? _measuredWidth;
  double? _measuredScale;

  @override
  void initState() {
    super.initState();
    // 首帧只渲染不可见的测量层,渲染后测量,下一帧再展示折叠后的内容,
    // 避免先展示完整内容再折叠的闪烁
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final wrapBox = _wrapKey.currentContext?.findRenderObject() as RenderBox?;
    final chipBox = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (wrapBox == null || chipBox == null || !mounted) return;
    setState(() {
      _measured = true;
      _twoLineHeight = chipBox.size.height * 2 + 6; // runSpacing 6
      _overflow = wrapBox.size.height > _twoLineHeight + 1;
    });
  }

  /// 构建 chips 列表。[wrapKey]/[tagFirst] 只用于测量层:
  /// GlobalKey 不能同时出现在测量层和显示层
  Widget _buildWrap({GlobalKey? wrapKey, bool tagFirst = false}) {
    return Wrap(
      key: wrapKey,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < widget.chips.length; i++)
          KeyedSubtree(
            key: tagFirst && i == 0 ? _chipKey : null,
            child: widget.chips[i],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 宽度或字号变化：本帧先按旧值渲染，帧后重新测量
        if (_measured &&
            (_measuredWidth != constraints.maxWidth ||
                _measuredScale != scale)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _measured = false);
            _measure();
          });
        }
        _measuredWidth = constraints.maxWidth;
        _measuredScale = scale;

        // 测量层：与显示层同宽完整布局，但不占高度、不可见
        final measureLayer = _buildMeasureLayer(constraints);
        // 显示层：测量完成前不渲染内容，避免展开 -> 折叠的闪烁
        final visible = !_measured
            ? const SizedBox.shrink()
            : _buildVisibleLayer();

        return Stack(children: [measureLayer, visible]);
      },
    );
  }

  // 测量层
  Widget _buildMeasureLayer(BoxConstraints constraints) {
    return SizedBox(
      height: 0,
      width: constraints.maxWidth,
      child: Opacity(
        opacity: 0,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: constraints.maxWidth,
          maxHeight: double.infinity,
          child: _buildWrap(wrapKey: _wrapKey, tagFirst: true),
        ),
      ),
    );
  }

  // 显示层
  Widget _buildVisibleLayer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRect(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (_expanded || !_overflow)
                  ? double.infinity
                  : _twoLineHeight,
            ),
            child: _buildWrap(),
          ),
        ),
        if (_overflow) _buildExpandButton(),
      ],
    );
  }

  // 展开按钮
  Widget _buildExpandButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => setState(() => _expanded = !_expanded),
        icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
        label: Text(_expanded ? '收起' : '展开'),
      ),
    );
  }
}
