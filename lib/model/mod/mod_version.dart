import 'package:mc_mod_helper/setting/value/source.dart';

class ModVersion {
  const ModVersion({required this.version, required this.source});

  /// 版本名称
  final String version;

  /// 来源
  final ModSource source;
}
