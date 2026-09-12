import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/value/display.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';
import 'package:mc_mod_helper/setting/theme_settings.dart';

/// 浏览历史页:展示最近打开过的模组(最近的在最前)。
///
/// 监听历史服务与设置服务:其它位置新打开的模组实时出现在最前,
/// 展示方式切换即时换布局;条目点击进详情页(与收藏页同一套卡片)
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览历史'),
        actions: [
          IconButton(
            tooltip: '清空历史',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          HistoryService.instance,
          ThemeSettings.instance,
        ]),
        builder: (context, _) {
          final history = HistoryService.instance.summaries();
          if (history.isEmpty) {
            return Center(
              child: Text(
                '还没有浏览记录\n打开模组详情页后会自动记录',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: DisplayManager.buildSliver(
                  DisplaySettings.instance.displayStyle,
                  history,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 清空历史(先确认:记录无法恢复)
  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空浏览历史'),
        content: const Text('将删除全部浏览记录,且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await HistoryService.instance.clear();
  }
}
