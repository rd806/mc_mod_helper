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
    this.source,
    this.sourceId,
  });

  /// 站内模组 ID
  /// 数据来源非 mcmod 时为占位值 0(来源平台用 [sourceId] 标识)
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

  /// 数据来源:null='mcmod', 'modrinth'=Modrinth
  final String? source;

  /// 来源平台内的唯一标识(Modrinth 项目的 slug);mcmod 数据为 null
  final String? sourceId;

  /// 模组详情页地址(按数据来源返回)
  String get pageUrl => (source == 'modrinth' && sourceId != null)
      ? 'https://modrinth.com/mod/$sourceId'
      : 'https://www.mcmod.cn/class/$id.html';
}