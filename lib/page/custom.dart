import 'package:flutter/material.dart';
import 'package:mc_mod_helper/page/custom/favorite.dart';
import 'package:mc_mod_helper/page/custom/history.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';

/// 我的:收藏与浏览历史的入口页。
///
/// 只做导航与计数展示,两个列表各自的实现在 custom/ 下;
/// 计数跟着两个服务变化即时刷新
class CustomPage extends StatelessWidget {
  const CustomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          FavoritesService.instance,
          HistoryService.instance,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _buildEntry(
              context,
              icon: Icons.favorite,
              title: '我的收藏',
              subtitle: '${FavoritesService.instance.list().length} 个模组',
              builder: (_) => const FavoritePage(),
            ),
            _buildEntry(
              context,
              icon: Icons.history,
              title: '浏览历史',
              subtitle: '${HistoryService.instance.list().length} 条记录',
              builder: (_) => const HistoryPage(),
            ),
          ],
        ),
      ),
    );
  }

  /// 一个入口:图标 + 名称 + 数量,点击推开对应页面
  Widget _buildEntry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required WidgetBuilder builder,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: builder)),
      ),
    );
  }
}
