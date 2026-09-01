/// 搜索结果中的模组摘要
class ModSummary {
  const ModSummary({
    required this.id,
    required this.title,
    required this.description,
    this.subName,
    this.iconUrl,
    this.statsText,
    this.source,
    this.sourceId,
  });

  /// 站内模组 ID
  /// 数据来源非 mcmod 时为占位值 0(来源平台用 [sourceId] 标识)
  final int id;

  /// 完整标题,如 `[JEI] JEI物品管理器 (Just Enough Items)`
  final String title;

  /// 简介(来自搜索页结果摘要)
  final String description;

  /// 英文名(副标题),可能为空
  final String? subName;

  /// 模组图标地址(首页推荐列表有,搜索结果没有)
  final String? iconUrl;

  /// 浏览/推荐/收藏统计文本(分类列表页有,如 '浏览 5575 · 推荐 80 · 收藏 0')
  final String? statsText;

  /// 数据来源:null='mcmod', 'modrinth'=Modrinth
  final String? source;

  /// 来源平台内的唯一标识(Modrinth 项目的 slug,如 'jei');mcmod 数据为 null
  final String? sourceId;

  /// 模组详情页地址(按数据来源返回)
  String get pageUrl => (source == 'modrinth' && sourceId != null)
      ? 'https://modrinth.com/mod/$sourceId'
      : 'https://www.mcmod.cn/class/$id.html';

  /// 去掉 `[缩写]` 前缀后的显示名
  String get displayName {
    final m = RegExp(r'^\[[^\]]*\]\s*').firstMatch(title);
    return m == null ? title : title.substring(m.end);
  }

  /// 缩写(如 JEI),没有则为 null
  String? get abbr {
    final m = RegExp(r'^\[([^\]]*)\]').firstMatch(title);
    return m?.group(1);
  }
}