import 'package:flutter/material.dart';
import 'package:mc_mod_helper/icon/icon_manager.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/widget/common/collapsible_widgets.dart';
import 'package:mc_mod_helper/widget/dialog/switch_dialog.dart';

import '../../model/filter/sort_method.dart';

/// 浏览页顶部的筛选栏:一条摘要 + 可展开的三组选项。
///
/// 「可展开」用 AnimatedSize + AnimatedRotation(与设置页的折叠分组同一套写法),
/// 展开时把下方列表推下去而不是盖住 —— 列表是无限滚动的,浮层会挡住用户
/// 正在比对的内容。
///
/// 展开/收起是纯界面状态,不触发任何请求;选中的条件由父页面持有
/// (筛选变化要重置分页,属于页面的事)。
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.filter,
    required this.categories,
    required this.versions,
    required this.onChanged,
    this.optionsLoading = false,
    this.optionsError,
    this.onRetryOptions,
  });

  /// 当前筛选(分类/版本/排序的选中态由它决定)
  final Filter filter;

  /// 可选分类(按当前数据来源抓取,可能还没加载完)
  final List<ProjectCategory> categories;

  /// 可选版本
  final List<ProjectVersion> versions;

  /// 选项加载中/失败(失败时给一次重试,不阻塞列表本身)
  final bool optionsLoading;
  final String? optionsError;
  final VoidCallback? onRetryOptions;

  /// 任一项变化:分类、版本、(可选)排序
  final void Function(
    ProjectCategory? category,
    ProjectVersion? version,
    SortMethod sort,
  )
  onChanged;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  bool _expanded = false;

  /// 摘要:来源之外的三个维度(未选显示「全部」)
  String get _summary {
    final parts = [
      widget.filter.category?.name ?? '全部分类',
      widget.filter.version?.version ?? '全部版本',
      SortManager.getSortTitle(widget.filter.sortMethod),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSummaryBar(theme),
        // 展开/收起用 AnimatedSize 过渡;高度不设限的话,版本组上百项会把
        // 列表挤没,所以面板内部自己滚动
        //
        // 面板常驻在树上,收起时用 Offstage 藏起来(照常布局,但不占高度、
        // 不绘制、不可点):CollapsibleWidgets 是「首帧先测量、下一帧才显示
        // chips」的,若面板随展开才挂载,高度就会在动画途中再长一截,而
        // RenderAnimatedSize 一旦发现动画中尺寸又变了会把动画跳到终值
        // (_layoutChanged → unstable),表现就是展开完全没有过渡。
        // 常驻后首帧即完整高度,只有一次 0 → 面板高度 的变化,动画才成立。
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Offstage(offstage: !_expanded, child: _buildPanel(theme)),
        ),
      ],
    );
  }

  /// 摘要条:来源胶囊 + 当前条件 + 展开箭头
  Widget _buildSummaryBar(ThemeData theme) {
    return Row(
      children: [
        // 数据来源是「作用域」而不是一个筛选条件:它决定分类/版本的候选集,
        // 所以常驻在摘要条上,不放进展开面板里当第四组
        ActionChip(
          avatar: IconManager.getIconForDataSource(widget.filter.modSource),
          label: Text(SourceManager.getSourceString(widget.filter.modSource)),
          onPressed: () => showSwitchSourceDialog(context),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            _summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: _expanded ? '收起筛选' : '展开筛选',
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more),
          ),
        ),
      ],
    );
  }

  /// 展开面板:分类 / 版本 / 排序三组 + 重置
  Widget _buildPanel(ThemeData theme) {
    if (widget.optionsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.optionsError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '筛选项加载失败:${widget.optionsError}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onRetryOptions,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      // 限高 + 内部滚动:mcmod 与 Modrinth 的版本项都有上百个
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroup(theme, '分类', [
              (
                '全部',
                widget.filter.category == null,
                () {
                  widget.onChanged(null, widget.filter.version, _sort);
                },
              ),
              for (final category in widget.categories)
                (
                  category.name,
                  widget.filter.category?.id == category.id,
                  () =>
                      widget.onChanged(category, widget.filter.version, _sort),
                ),
            ]),
            const SizedBox(height: 12),
            _buildGroup(theme, '版本', [
              (
                '全部',
                widget.filter.version == null,
                () {
                  widget.onChanged(widget.filter.category, null, _sort);
                },
              ),
              for (final version in widget.versions)
                (
                  version.version,
                  widget.filter.version?.version == version.version,
                  () =>
                      widget.onChanged(widget.filter.category, version, _sort),
                ),
            ]),
            const SizedBox(height: 12),
            // 排序没有「全部」:FeatureSource.none 本身就是站点的默认排序
            _buildGroup(theme, '排序', [
              for (final sort in SortMethod.values)
                (
                  SortManager.getSortTitle(sort),
                  widget.filter.sortMethod == sort,
                  () => widget.onChanged(
                    widget.filter.category,
                    widget.filter.version,
                    sort,
                  ),
                ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _reset, child: const Text('重置')),
            ),
          ],
        ),
      ),
    );
  }

  SortMethod get _sort => widget.filter.sortMethod;

  /// 一组选项:标题 + 单选的 chip 墙
  Widget _buildGroup(
    ThemeData theme,
    String title,
    List<(String, bool, VoidCallback)> options,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        CollapsibleWidgets(
          widget: [
            for (final (label, selected, onTap) in options)
              // 单选语义:每个维度只会命中一个(分类/版本可含「全部」)
              ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => onTap(),
              ),
          ],
        ),
      ],
    );
  }

  void _reset() {
    widget.onChanged(null, null, SortMethod.none);
  }
}
