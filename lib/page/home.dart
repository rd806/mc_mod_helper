import 'package:flutter/material.dart';
import 'package:mc_mod_helper/page/main/config.dart';
import 'package:mc_mod_helper/page/main/favorite.dart';
import 'package:mc_mod_helper/page/main/feature.dart';
import 'package:mc_mod_helper/page/main/search.dart';
import 'package:mc_mod_helper/page/main/sort.dart';

/// 主页
/// 包含导航栏
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 当前选中的索引
  int _currentIndex = 0;

  // 定义页面列表（对应底栏每个选项）
  final List<Widget> _pages = [
    FeaturePage(),
    SortPage(),
    SearchPage(),
    FavoritePage(),
    ConfigPage(),
  ];

  final List<NavigationItem> _navItems = const [
    NavigationItem(icon: Icons.home, label: '首页'),
    NavigationItem(icon: Icons.category, label: '分类'),
    NavigationItem(icon: Icons.search, label: '搜索'),
    NavigationItem(icon: Icons.favorite, label: '收藏'),
    NavigationItem(icon: Icons.settings, label: '设置'),
  ];

  // 点击切换页面
  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 判断是否为宽屏（阈值通常为 600 或 800）
        final bool isWideScreen = constraints.maxWidth > 700;

        return Scaffold(
          // 根据屏幕宽度选择不同的 body 布局
          body: isWideScreen
              ? _buildWideLayout(theme)
              : _buildNarrowLayout(theme),
        );
      },
    );
  }

  Widget _buildNarrowLayout(ThemeData theme) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: _navItems
            .map(
              (item) => BottomNavigationBarItem(
                icon: Icon(item.icon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildWideLayout(ThemeData theme) {
    return Row(
      children: [
        // 左侧导航栏
        NavigationRail(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onItemTapped,
          labelType: NavigationRailLabelType.all,

          leading: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 50, // 设置宽度
              height: 50, // 设置高度
              fit: BoxFit.cover, // 设置图片的填充模式
            ),
          ),

          destinations: _navItems
              .map(
                (item) => NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(
                    item.icon,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(item.label),
                ),
              )
              .toList(),
        ),

        // 右侧内容区域（填充剩余空间）
        Expanded(
          child: IndexedStack(index: _currentIndex, children: _pages),
        ),
      ],
    );
  }
}

/// 导航项数据模型
class NavigationItem {
  final IconData icon;
  final String label;

  const NavigationItem({required this.icon, required this.label});
}
