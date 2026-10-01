import 'package:mc_mod_helper/model/project/project_summary.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

class AuthorDetail {
  const AuthorDetail({
    required this.id,
    required this.source,
    this.avatarUrl,
    this.name,
    this.bio,
    this.projects,
  });

  /// 用户id
  final String id;

  /// 用户来源
  final ModSource source;

  /// 头像图标(可为空:CurseForge 的作者没有头像,界面上用占位图标)
  final String? avatarUrl;

  /// 显示名称
  final String? name;

  /// 简介
  final String? bio;

  /// 参与的项目
  final List<ProjectSummary>? projects;
}
