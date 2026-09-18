import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

Filter _filter({
  ProjectType type = ProjectType.mod,
  ModSource source = ModSource.mcmod,
  SortMethod sort = SortMethod.none,
  ProjectCategory? category,
  ProjectVersion? version,
}) => Filter(
  type: type,
  modSource: source,
  sortMethod: sort,
  category: category,
  version: version,
);

void main() {
  test('类型进签名:同来源同分类但类型不同,不算同一组筛选', () {
    // 各站点的分类 id 是按类型分开编号的(mcmod 的 category=1 在模组下是
    // 「科技」、在整合包下是「科技整合包」),不带上类型两组查询会撞进同一份缓存
    const category = ProjectCategory(
      id: '1',
      type: ProjectType.modpack,
      name: '科技',
      source: ModSource.mcmod,
    );
    final mod = _filter(category: category);
    final pack = _filter(type: ProjectType.modpack, category: category);

    expect(mod.signature, isNot(pack.signature));
    expect(mod == pack, isFalse);
    expect(mod.hashCode, isNot(pack.hashCode));
  });

  test('除类型外完全相同时视为同一组筛选(点同一项不重拉依赖它)', () {
    final a = _filter(sort: SortMethod.lastEditTime);
    final b = _filter(sort: SortMethod.lastEditTime);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
  });

  test('签名含类型 / 来源 / 排序 / 分类 id / 版本号', () {
    final filter = _filter(
      type: ProjectType.modpack,
      source: ModSource.modrinth,
      sort: SortMethod.createTime,
      category: const ProjectCategory(
        id: 'adventure',
        type: ProjectType.modpack,
        name: '冒险',
        source: ModSource.modrinth,
      ),
      version: const ProjectVersion(
        version: '1.20.1',
        source: ModSource.modrinth,
      ),
    );
    expect(filter.signature, 'modpack|modrinth|createTime|adventure|1.20.1');
  });
}
