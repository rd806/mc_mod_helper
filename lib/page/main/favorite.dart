import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/savings.dart';
import 'package:mc_mod_helper/service/settings.dart';
import 'package:mc_mod_helper/value/display.dart';

/// 收藏页:展示已收藏的模组。
///
/// 监听收藏服务与设置服务:其它位置(列表心形/详情页)的收藏变化
/// 实时反映,展示方式切换即时换布局;
/// 条目上的心形已点亮,再点一次取消收藏
class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          FavoritesService.instance,
          SettingsService.instance,
        ]),
        builder: (context, _) {
          final likes = FavoritesService.instance.list();
          if (likes.isEmpty) {
            return Center(
              child: Text(
                '还没有收藏的模组\n在列表或详情页点击心形收藏',
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
                  SettingsService.instance.displayStyle,
                  [for (final l in likes) l.toSummary()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
