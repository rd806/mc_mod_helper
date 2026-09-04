import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mc_mod_helper/page/home.dart';

import 'service/settings.dart';

/// 应用程序入口
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先加载保存的设置再启动应用，避免启动后主题/字体跳变
  await SettingsService.instance.load();
  runApp(const McModHelper());
}

/// MC百科模组信息浏览应用
class McModHelper extends StatelessWidget {
  const McModHelper({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听全部设置;任意一项变化都重建 MaterialApp 本体。
    // home 是 const，ThemeData 有缓存（见 _buildTheme）,
    // 所以非主题类设置变化不会引发子树重建/主题动画
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        return MaterialApp(
          title: 'Minecraft Mod Helper',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light, settings.seedColor),
          darkTheme: _buildTheme(Brightness.dark, settings.seedColor),
          themeMode: settings.themeMode,
          // 全局字体缩放:覆盖 MediaQuery.textScaler。
          // Navigator 是 builder 的 child,因此路由页面/对话框/SnackBar 全部生效。
          // 注意:这会覆盖系统无障碍字体缩放(用户三档选择优先)。
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(settings.fontScale)),
            child: child!,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

/// (种子色 ARGB32, 亮度) → ThemeData 缓存。
///
/// 设置服务在任意设置变化时都会通知,若每次通知都新建 ThemeData,
/// MaterialApp 内部的 AnimatedTheme 会因实例不等触发全树主题重建动画;
/// 缓存保证只有种子色/亮度真正变化时才产生新的 ThemeData 实例。
final Map<(int, Brightness), ThemeData> _themeCache = {};

/// 按亮度与种子色构建主题:亮/暗共用同一 seed 色,保证是同一品牌色的明暗两版
ThemeData _buildTheme(Brightness brightness, Color seedColor) {
  return _themeCache.putIfAbsent((seedColor.toARGB32(), brightness), () {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      // Web 端对字体回退的支持不可靠,指定 Noto 后
      // 缺失字形（符号/emoji）会报字体警告甚至显示豆腐块,
      // 因此 web 不指定字体、交给浏览器系统字体；原生平台用 Noto。
      fontFamily: kIsWeb ? null : 'NotoSansSC',
      fontFamilyFallback: const [
        'Segoe UI Symbol',
        'Segoe UI Emoji',
        'Microsoft YaHei',
      ],
      useMaterial3: true,
    );
  });
}
