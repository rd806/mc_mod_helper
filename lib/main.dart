import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'pages/search_page.dart';

// 应用程序入口
void main() {
    runApp(const McModApp());
}

/// MC百科(mcmod.cn)模组信息浏览应用
class McModApp extends StatelessWidget {
    const McModApp({super.key});

    @override
    Widget build(BuildContext context) {
        return MaterialApp(
        title: 'Minecraft Mod Helper',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
            // Web 端(CanvasKit)对字体回退的支持不可靠,指定 Noto 后
            // 缺失字形(符号/emoji)会报字体警告甚至显示豆腐块,
            // 因此 web 不指定字体、交给浏览器系统字体;原生平台用 Noto。
            fontFamily: kIsWeb ? null : 'NotoSansSC',
            fontFamilyFallback: const [
                'Segoe UI Symbol',
                'Segoe UI Emoji',
                'Microsoft YaHei',
            ],
            useMaterial3: true,
        ),
        home: const SearchPage(),
        );
    }
}
