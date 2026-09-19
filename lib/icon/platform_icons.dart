import 'package:flutter/material.dart';

/// 链接图标(自定义图标字体)。
///
/// 字体文件 assets/icon/link_icons.ttf 由 IcoMoon/FlutterIcon 等工具生成,
/// 其内部 family 名必须与 pubspec.yaml 中声明的 LinkIcons 一致。
///
/// 每个图标的 codePoint 以生成工具输出的为准(见样式表里的 content: "\e900"
/// 之类,去掉反斜杠就是 0xe900)。
class PlatformIcons {
  PlatformIcons._();

  /// 与 pubspec.yaml 中声明的字体 family 对应
  static const String platformFont = 'PlatformIcons';

  static const IconData forge = IconData(0xf002, fontFamily: platformFont);
  static const IconData fabric = IconData(0xf003, fontFamily: platformFont);
  static const IconData neoforge = IconData(0xf001, fontFamily: platformFont);
  static const IconData quilt = IconData(0xf000, fontFamily: platformFont);

  static const IconData bukkit = IconData(0xf004, fontFamily: platformFont);
  static const IconData spigot = IconData(0xf008, fontFamily: platformFont);
  static const IconData paper = IconData(0xf006, fontFamily: platformFont);
  static const IconData purpur = IconData(0xf007, fontFamily: platformFont);
  static const IconData folia = IconData(0xf005, fontFamily: platformFont);
  static const IconData bungeecord = IconData(0xf009, fontFamily: platformFont);
  static const IconData velocity = IconData(0xf00a, fontFamily: platformFont);
  static const IconData waterfall = IconData(0xf00b, fontFamily: platformFont);
}
