import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('关于项目')),
      body: Column(
        children: [
          _buildIcon(theme),
          _buildLink(
            '开源协议',
            'GPL-3.0',
            'https://github.com/rd806/mc_mod_helper/blob/main/LICENSE',
          ),
          _buildLink('项目地址', '点击打开', 'https://github.com/rd806/mc_mod_helper'),
        ],
      ),
    );
  }

  /// 项目封面
  Widget _buildIcon(ThemeData theme) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/app_icon.png',
            width: 100, // 设置宽度
            height: 100, // 设置高度
            fit: BoxFit.cover, // 设置图片的填充模式
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                'MC Mod Helper',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text('简易的Minecraft模组浏览器', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建链接
  Widget _buildLink(String title, String label, String url) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Text(title),
          const Spacer(),
          ActionChip(
            label: Text(label),
            onPressed: () {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }
}
