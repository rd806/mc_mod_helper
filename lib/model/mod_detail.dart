import 'mod_link.dart';

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
    this.source = 'mcmod',
  });

  /// 统一模组标识(字符串):MC百科为数字字符串(如 '123'),Modrinth 为 slug(如 'jei')
  final String id;

  /// 主要名称
  final String title;

  /// 次要名称
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

  /// 数据来源:'mcmod' 或 'modrinth'
  final String source;

  /// 模组详情页地址(按数据来源返回)
  String get pageUrl => source == 'modrinth'
      ? 'https://modrinth.com/mod/$id'
      : 'https://www.mcmod.cn/class/$id.html';
}
