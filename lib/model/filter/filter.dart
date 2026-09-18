import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

/// 筛选器:浏览页的全部筛选条件。
///
/// 分类与版本可选,三个维度由各来源的接口自己翻译成参数;
/// 能否组合取决于站点能力(实测 mcmod 的分类 + 版本 + 排序可同时生效,
/// 所以这里不做互斥,筛选栏显示什么就筛什么)。
class Filter {
  const Filter({
    required this.modSource,
    required this.sortMethod,
    this.category,
    this.version,
  });

  /// 数据来源（必需）
  final ModSource modSource;

  /// 排序方法（必需）
  final SortMethod sortMethod;

  /// 模组分类
  final ProjectCategory? category;

  /// 模组版本
  final ProjectVersion? version;

  /// 请求签名 / 缓存 key:只含影响结果的字段。
  ///
  /// 分类与版本取各自的标识(而非展示名):改个显示名不该换一份缓存,
  /// 而 id 一样就一定是同一批结果。
  String get signature =>
      '${modSource.name}|${sortMethod.name}'
      '|${category?.id ?? ''}|${version?.version ?? ''}';

  /// 筛选条件是否相同(按 [signature] 比,与其对应的字段一致)。
  ///
  /// 浏览页据此判断「点的是不是已经选中的那一项」——不比较的话,
  /// 每次点 chip 造出的新实例都不相等,会白白重拉一遍。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Filter && other.signature == signature);

  @override
  int get hashCode => signature.hashCode;
}
