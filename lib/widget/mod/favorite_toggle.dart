import 'package:flutter/material.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';
import 'package:mc_mod_helper/service/savings.dart';

/// 收藏开关按钮:心形,点亮=已收藏。
///
/// 监听收藏服务(ChangeNotifier):任意位置(列表/详情页)的收藏变化
/// 都会实时同步到所有心形按钮
class FavoriteToggle extends StatelessWidget {
  const FavoriteToggle({super.key, required this.mod});

  final ModSummary mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        final fav = FavoritesService.instance.isFavorite(mod);
        return IconButton(
          tooltip: fav ? '取消收藏' : '收藏',
          icon: Icon(
            fav ? Icons.favorite : Icons.favorite_border,
            color: fav ? Colors.redAccent : theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: () => FavoritesService.instance.toggle(mod),
        );
      },
    );
  }
}
