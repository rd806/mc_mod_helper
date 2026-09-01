/// 模组分类(mcmod.cn 首页 / Modrinth categories)
class ModCategory {
  const ModCategory({
    required this.id,
    required this.name,
    this.slogan,
    this.description,
    this.source,
    this.sourceId,
  });

  /// 分类 ID
  /// 数据来源非 mcmod 时为占位值 0(来源平台用 [sourceId] 标识)
  final int id;

  /// 分类名,如 科技
  final String name;

  /// 标语,如 '科学技术是第一生产力。'
  final String? slogan;

  /// 分类定义(站点上为隐藏文本)
  final String? description;

  /// 数据来源:null='mcmod', 'modrinth'=Modrinth
  final String? source;

  /// 来源平台内的唯一标识(Modrinth 分类名,如 'technology');mcmod 数据为 null
  final String? sourceId;

  /// 分类第 1 页地址
  String get pageUrl => 'https://www.mcmod.cn/class/category/$id-1.html';
}