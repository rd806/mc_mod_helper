/// 模组分类(mcmod.cn 首页 / Modrinth categories)
class ModCategory {
  const ModCategory({
    required this.id,
    required this.name,
    this.slogan,
    this.description,
    this.source = 'mcmod',
  });

  /// 统一分类标识(字符串):MC百科为数字字符串(如 '1'),Modrinth 为分类名(如 'technology')
  final String id;

  /// 分类名,如 科技
  final String name;

  /// 标语,如 '科学技术是第一生产力。'
  final String? slogan;

  /// 分类定义(站点上为隐藏文本)
  final String? description;

  /// 数据来源:'mcmod' 或 'modrinth'
  final String source;

  /// 分类第 1 页地址
  String get pageUrl => 'https://www.mcmod.cn/class/category/$id-1.html';
}
