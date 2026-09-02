import 'package:mc_mod_helper/api/source.dart';

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
    this.source = ModSource.mcmod,
  });

  /// 统一模组标识(字符串):MC百科为数字字符串(如 '123'),Modrinth 为 slug(如 'jei')
  final String id;

  /// 主要名称
  final String title;

  /// 次要名称
  final String? subName;

  /// 模组介绍(清洗后的 HTML,两种来源统一):
  /// - mcmod:来自正文面板的富文本 HTML,无面板时回退 wiki 简介
  /// - modrinth:API 的 body Markdown 经 markdownToHtml 转换,原生 HTML 透传
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
  final List<String>? environment;

  /// 数据来源:'mcmod' 或 'modrinth'
  final ModSource source;

  /// 模组详情页地址(按数据来源返回)
  String get pageUrl => SourceManager.getUrl(source, id);
}
