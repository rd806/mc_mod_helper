import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/mod/mod_loader.dart';

void main() {
  test('of:按小写查表,名称取注册表里的规范写法', () {
    // 三个站点的写法各不相同(Modrinth 给小写、mcmod 给 Forge、还可能大小写不一)
    for (final raw in ['forge', 'Forge', 'FORGE', ' Forge ']) {
      final loader = ModLoader.of(raw);
      expect(loader.name, 'Forge', reason: raw);
      expect(identical(loader, modLoaders['forge']), isTrue, reason: raw);
    }
    expect(ModLoader.of('neoforge').name, 'NeoForge');
    expect(ModLoader.of('Quilt').name, 'Quilt');
    expect(ModLoader.of('fabric').name, 'Fabric');
  });

  test('of:注册表外的加载器保留原名,用通用图标兜底', () {
    final loader = ModLoader.of('数据包');
    expect(loader.name, '数据包');
    expect(loader.icon, isA<Icon>());
    expect(loader.icon, isNot(modLoaders['fabric']!.icon));
    // 没有配色 → 界面回落到主题色
    expect(loader.color, isNull);
  });

  test('按名称相等:同名实例可作 Map 的键(分组不会裂成两组)', () {
    final fromRegistry = ModLoader.of('Fabric');
    final another = ModLoader(
      icon: const Icon(Icons.extension),
      name: 'Fabric',
    );
    expect(another, fromRegistry);
    expect(another.hashCode, fromRegistry.hashCode);

    final map = <ModLoader, List<String>>{};
    map.putIfAbsent(fromRegistry, () => []).add('1.21.1');
    expect(map[another], ['1.21.1']);
  });

  test('color:取图标上的配色给名称用', () {
    expect(ModLoader.of('forge').color, Colors.blue);
    expect(ModLoader.of('fabric').color, Colors.green);
    expect(ModLoader.of('neoforge').color, Colors.orange);
    expect(ModLoader.of('quilt').color, Colors.blueAccent);
  });
}
