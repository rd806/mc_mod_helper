/// 排序方法
enum SortMethod { none, createTime, lastEditTime }

class SortManager {
  /// 字符串转 SortMethod
  static SortMethod sortToString(String? value) {
    return SortMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SortMethod.none,
    );
  }

  /// [SortMethod] → mcmod 列表页的 sort 参数
  /// (空串即默认排序,站内推荐序)
  static String mcmodSort(SortMethod source) => switch (source) {
    SortMethod.none => '',
    SortMethod.createTime => 'createtime',
    SortMethod.lastEditTime => 'lastedittime',
  };

  /// 排序方式的显示名(筛选栏的选项与摘要条都用它)
  static String getSortTitle(SortMethod source) => switch (source) {
    SortMethod.none => '默认排序',
    SortMethod.createTime => '最新收录',
    SortMethod.lastEditTime => '最新编辑',
  };
}
