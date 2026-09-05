import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/savings.dart';
import 'package:mc_mod_helper/widget/mod/mod_tile.dart';

/// 收藏页:展示已收藏的模组。
///
/// 监听收藏服务(ChangeNotifier):其它位置(列表心形/详情页)的
/// 收藏变化实时反映;条目上的心形已点亮,再点一次取消收藏
class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: ListenableBuilder(
        listenable: FavoritesService.instance,
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
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [for (final l in likes) ModTile(mod: l.toSummary())],
          );
        },
      ),
    );
  }
}
