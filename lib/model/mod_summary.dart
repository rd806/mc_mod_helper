import 'package:mc_mod_helper/api/source.dart';

import 'mod_detail.dart';

/// 搜索结果中的模组摘要
class ModSummary {
  const ModSummary({
    required this.id,
    required this.title,
    required this.description,
    this.subName,
    this.iconUrl,
    this.statsText,
    this.source = ModSource.mcmod,
  });

  /// 从详情构造摘要(收藏按钮用:详情页拿到的通常是 ModDetail)。
  ///
  /// description 用副标题:正文是 HTML,直接当列表副标题会显示标签
  factory ModSummary.fromDetail(ModDetail d) {
    return ModSummary(
      id: d.id,
      title: d.title,
      description: d.subName ?? '',
      iconUrl: d.coverUrl,
      source: d.source,
    );
  }

  /// 统一模组标识(字符串):MC百科为数字字符串(如 '123'),Modrinth 为 slug(如 'jei')
  final String id;

  /// 完整标题,如 `[JEI] JEI物品管理器 (Just Enough Items)`
  final String title;

  /// 简介(来自搜索页结果摘要)
  final String description;

  /// 副标题，可能为空
  final String? subName;

  /// 模组图标地址(首页推荐列表有,搜索结果没有)
  final String? iconUrl;

  /// 浏览/推荐/收藏统计文本(分类列表页有,如 '浏览 5575 · 推荐 80 · 收藏 0')
  final String? statsText;

  /// 数据来源:'mcmod' 或 'modrinth'
  final ModSource source;

  /// 模组详情页地址(按数据来源返回)
  String get pageUrl => SourceManager.getUrl(source, id);

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
