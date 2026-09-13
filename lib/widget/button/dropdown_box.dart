import 'package:flutter/material.dart';

/// 下拉选项:展示文案 + 取值,可选前置图标与文字样式。
///
/// 图标用于主题 / 数据来源 / 展示方式,文字样式用于字体下拉的字体预览。
class DropdownOption<T> {
  const DropdownOption(this.label, this.value, {this.icon, this.textStyle});

  final String label;
  final T value;
  final Widget? icon;
  final TextStyle? textStyle;
}

/// 下拉选择的设置项:左侧名称,右侧下拉框。
///
/// 设置页里「主题选择 / 渲染方法 / 字体选择 / 数据来源 / 推荐来源 /
/// 展示方式 / 目标语言」的排布与样式完全一致,差异只有选项与选中值,
/// 因此收敛到这里;样式固定在组件内(透明下划线、统一箭头与字号)。
///
/// [value] 不在 [options] 里时回落到 [fallback](默认取第一项),
/// 避免 DropdownButton 因选中值缺失而断言失败。
class DropdownBox<T> extends StatelessWidget {
  const DropdownBox({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.fallback,
  });

  /// 设置项名称(行内左侧标签)
  final String title;

  /// 当前选中值
  final T value;

  /// 全部可选项(顺序即菜单顺序)
  final List<DropdownOption<T>> options;

  /// 选中项的取值变更;由本组件过滤掉 null(下拉收起时回调 null)
  final ValueChanged<T> onChanged;

  /// [value] 非法时的兜底选中值(默认取第一项)
  final T? fallback;

  /// 实际传给 DropdownButton 的选中值:必定是选项之一
  T? get _selected {
    if (options.isEmpty) return null;
    for (final option in options) {
      if (option.value == value) return option.value;
    }
    for (final option in options) {
      if (option.value == fallback) return option.value;
    }
    return options.first.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.bodyMedium),
          const Spacer(),
          DropdownButton<T>(
            value: _selected,
            items: [
              for (final option in options)
                DropdownMenuItem<T>(
                  value: option.value,
                  child: Row(
                    children: [
                      if (option.icon != null) ...[
                        option.icon!,
                        const SizedBox(width: 10),
                      ],
                      Text(option.label, style: option.textStyle),
                    ],
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            style: theme.textTheme.bodyMedium,
            // 透明下划线 + 无焦点底色:行内只留文案与箭头
            underline: Container(height: 0, color: Colors.transparent),
            icon: Icon(Icons.arrow_drop_down, color: theme.iconTheme.color),
            focusColor: Colors.transparent,
          ),
        ],
      ),
    );
  }
}
