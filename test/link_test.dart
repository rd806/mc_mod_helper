import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/icon/link_icons.dart';
import 'package:mc_mod_helper/model/link.dart';
import 'package:mc_mod_helper/model/mod/mod_loader.dart';

/// 图标内容(用于断言取到的是哪一个)
IconData _data(Widget icon) => (icon as Icon).icon!;

void main() {
  test('按包含匹配:带后缀的链接名也能认出图标', () {
    // 站点给的链接名常带后缀,不再要求全等
    for (final name in ['GitHub', 'GitHub 仓库', 'github releases']) {
      expect(Link.getIcon(name), linkIcon['github'], reason: name);
    }
    expect(Link.getIcon('源码 (Gitee)'), linkIcon['gitee']);
    expect(Link.getIcon('CurseForge 页面'), linkIcon['curseforge']);
    expect(Link.getIcon('MC百科'), linkIcon['mc']);
    expect(Link.getIcon('官方 Wiki'), linkIcon['wiki']);
    expect(Link.getIcon('蓝奏云下载'), linkIcon['蓝奏云']);
    // 大小写与首尾空格不影响
    expect(Link.getIcon('  DISCORD '), linkIcon['discord']);
  });

  test('顺序即优先级:更具体的词排在前面', () {
    // 'Minecraft Wiki' 同时含 'wiki' 与 'minecraft',取先命中的 wiki
    expect(_data(Link.getIcon('Minecraft Wiki')), LinkIcons.wiki);
    // 'maven' 排在 'mc' 之前(否则 'Maven Central' 会先撞上 'mc')
    expect(_data(Link.getIcon('Maven Central')), Icons.code_rounded);
  });

  test('加载器名按全等认:CurseForge 不会被 Forge 抢走', () {
    // 名字就是加载器名时给加载器图标(与旧行为一致)
    expect(Link.getIcon('Forge'), modLoaders['forge']!.icon);
    expect(Link.getIcon('fabric'), modLoaders['fabric']!.icon);
    // 关键:加载器不参与包含匹配。若参与,'CurseForge' 会命中 'forge'
    expect(_data(Link.getIcon('CurseForge')), LinkIcons.curseforge);
    expect(_data(Link.getIcon('NeoForge 下载')), Icons.link);
  });

  test('都不命中时回落到通用链接图标', () {
    expect(_data(Link.getIcon('随便什么')), Icons.link);
    expect(_data(Link.getIcon('')), Icons.link);
  });

  test('构造链接时就把图标定下来', () {
    final link = Link(icon: Link.getIcon('GitHub'), name: 'GitHub', url: 'u');
    expect(_data(link.icon), LinkIcons.github);
  });
}
