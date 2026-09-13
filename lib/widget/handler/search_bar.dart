import 'package:flutter/material.dart';
import 'package:mc_mod_helper/page/discover/search.dart';

/// 伪搜索栏
///
/// 点击打开搜索界面
class FakeSearchBar extends StatelessWidget {
  const FakeSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SearchPage()),
        );
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.onInverseSurface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(Icons.search),
            SizedBox(width: 8),
            Text(
              '搜索',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
