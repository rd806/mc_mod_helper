import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/project/project_loader.dart';

void main() {
  test('of:按小写查表,名称取注册表里的规范写法', () {
    // 三个站点的写法各不相同(Modrinth 给小写、mcmod 给 Forge、还可能大小写不一)
    for (final raw in ['forge', 'Forge', 'FORGE', ' Forge ']) {
      final loader = ProjectLoader.of(raw);
      expect(loader.name, 'Forge', reason: raw);
      expect(identical(loader, projectLoaders['forge']), isTrue, reason: raw);
    }
    expect(ProjectLoader.of('neoforge').name, 'NeoForge');
    expect(ProjectLoader.of('Quilt').name, 'Quilt');
    expect(ProjectLoader.of('fabric').name, 'Fabric');
  });

  test('of:服务端平台也认得(Modrinth 的插件按这些加载器给出)', () {
    // 插件版本条目的 loaders 是 paper / bukkit / velocity 这类服务端平台
    for (final raw in [
      'paper',
      'bukkit',
      'spigot',
      'purpur',
      'folia',
      'bungeecord',
      'velocity',
      'waterfall',
    ]) {
      final loader = ProjectLoader.of(raw);
      expect(loader.name, isNot(raw), reason: raw); // 取到的是规范写法
      expect(identical(loader, projectLoaders[raw]), isTrue, reason: raw);
    }
    expect(ProjectLoader.of('paper').name, 'Paper');
    expect(ProjectLoader.of('Paper').icon, isA<Icon>());
    expect(ProjectLoader.of('velocity').color, isNotNull);
  });

  test('isServerPlatform:认得服务端平台,模组加载器不算', () {
    for (final name in ['bukkit', 'Paper', ' VELOCITY ']) {
      expect(ProjectLoader.isServerPlatform(name), isTrue, reason: name);
    }
    for (final name in [
      'forge',
      'fabric',
      'neoforge',
      'quilt',
      'datapack',
      '',
    ]) {
      expect(ProjectLoader.isServerPlatform(name), isFalse, reason: name);
    }
  });

  test('of:注册表外的加载器保留原名,用通用图标兜底', () {
    final loader = ProjectLoader.of('数据包');
    expect(loader.name, '数据包');
    expect(loader.icon, isA<Icon>());
    expect(loader.icon, isNot(projectLoaders['fabric']!.icon));
    // 没有配色 → 界面回落到主题色
    expect(loader.color, isNull);
  });

  test('按名称相等:同名实例可作 Map 的键(分组不会裂成两组)', () {
    final fromRegistry = ProjectLoader.of('Fabric');
    final another = ProjectLoader(
      icon: const Icon(Icons.extension),
      name: 'Fabric',
    );
    expect(another, fromRegistry);
    expect(another.hashCode, fromRegistry.hashCode);

    final map = <ProjectLoader, List<String>>{};
    map.putIfAbsent(fromRegistry, () => []).add('1.21.1');
    expect(map[another], ['1.21.1']);
  });

  test('color:取图标上的配色给名称用', () {
    expect(ProjectLoader.of('forge').color, Colors.blue);
    expect(ProjectLoader.of('fabric').color, Colors.green);
    expect(ProjectLoader.of('neoforge').color, Colors.orange);
    expect(ProjectLoader.of('quilt').color, Colors.blueAccent);
  });
}
