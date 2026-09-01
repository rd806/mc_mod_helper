/// 模组外链
class ModLink {
  const ModLink({required this.name, required this.url});

  final String name;
  final String url;
}

/// 搜索结果中的模组摘要
class ModSummary {
  const ModSummary({
    required this.id,
    required this.title,
    required this.description,
    this.subName,
    this.iconUrl,
    this.statsText,
  });

  /// 站内模组 ID
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

  /// 模组详情页地址
  String get pageUrl => 'https://www.mcmod.cn/class/$id.html';

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

/// mcmod.cn 首页展示的模组分类
class ModCategory {
  const ModCategory({
    required this.id,
    required this.name,
    this.slogan,
    this.description,
  });

  final int id;

  /// 分类名,如 科技
  final String name;

  /// 标语,如 '科学技术是第一生产力。'
  final String? slogan;

  /// 分类定义(站点上为隐藏文本)
  final String? description;

  /// 分类第 1 页地址
  String get pageUrl => 'https://www.mcmod.cn/class/category/$id-1.html';
}

/// 模组详细信息(解析自详情页)
class ModDetail {
  const ModDetail({
    required this.id,
    required this.title,
    this.subName,
    this.description,
    this.coverUrl,
    this.links = const [],
    this.mcVersions = const [],
    this.platform,
    this.environment,
  });

  final int id;

  /// 中文名
  final String title;

  /// 英文名(副标题)
  final String? subName;

  /// 模组介绍（富文本 HTML）
  /// 来自详情页正文面板的全部内容；页面无正文面板时由搜索页 wiki 简介转换而来
  final String? description;

  /// 封面图地址
  final String? coverUrl;

  /// 相关链接(CurseForge / GitHub 等)
  final List<ModLink> links;

  /// 支持的 MC 版本
  final List<String> mcVersions;

  /// 支持平台(如 Java版)
  final String? platform;

  /// 运行环境(如 客户端需装, 服务端无效)
  final String? environment;

  String get pageUrl => 'https://www.mcmod.cn/class/$id.html';
}
