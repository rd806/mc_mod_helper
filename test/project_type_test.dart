import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/project/project_type.dart';

void main() {
  test('五种类型都有中文名与图标', () {
    expect(ProjectType.values, hasLength(5));
    for (final type in ProjectType.values) {
      expect(
        ProjectTypeManager.getTypeTitle(type),
        isNotEmpty,
        reason: '$type',
      );
      expect(
        ProjectTypeManager.getTypeIcon(type),
        isA<Icon>(),
        reason: '$type',
      );
    }
    expect(ProjectTypeManager.getTypeTitle(ProjectType.mod), '模组');
    expect(ProjectTypeManager.getTypeTitle(ProjectType.modpack), '整合包');
    expect(ProjectTypeManager.getTypeTitle(ProjectType.resourcepack), '材质包');
    expect(ProjectTypeManager.getTypeTitle(ProjectType.shader), '光影');
    expect(ProjectTypeManager.getTypeTitle(ProjectType.plugin), '插件');
  });

  test('持久化:存枚举名,读回同一个类型', () {
    for (final type in ProjectType.values) {
      final name = ProjectTypeManager.typeToString(type);
      expect(name, type.name); // 存 name 而非 index
      expect(ProjectTypeManager.typeFromString(name), type);
    }
  });

  test('持久化的类型名认不出来(旧记录/脏数据)时回落到模组', () {
    // 接入类型之前存下的记录没有这一列,读出来是 null
    expect(ProjectTypeManager.typeFromString(null), ProjectType.mod);
    expect(ProjectTypeManager.typeFromString(''), ProjectType.mod);
    expect(
      ProjectTypeManager.typeFromString('something-else'),
      ProjectType.mod,
    );
  });
}
