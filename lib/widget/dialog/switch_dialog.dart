import 'package:flutter/material.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:mc_mod_helper/setting/display_settings.dart';

import '../../icon/icon_manager.dart';

/// 可选的数据源(展示名 + 枚举值)
const List<(String, ModSource)> _modSource = [
  ('MC百科', ModSource.mcmod),
  ('Modrinth', ModSource.modrinth),
];

/// 弹出数据源选择框:点某个来源即切换并关闭,返回所选来源;
/// 点弹窗外部/返回键关闭则返回 null(不做修改)。
///
/// 与验证码弹窗(见 captcha_dialog.dart)同一套写法:调用方只调本函数,
/// 弹窗本体是文件内的私有组件。切换来源是轻量操作,弹窗即可,不必进出整页。
Future<ModSource?> showSwitchSourceDialog(BuildContext context) {
  return showDialog<ModSource>(
    context: context,
    builder: (context) => const _SwitchSourceDialog(),
  );
}

class _SwitchSourceDialog extends StatelessWidget {
  const _SwitchSourceDialog();

  @override
  Widget build(BuildContext context) {
    final current = DisplaySettings.instance.dataSource;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('请选择数据源', style: theme.textTheme.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          for (final (label, source) in _modSource)
            ChoiceChip(
              avatar: IconManager.getIconForDataSource(source),
              label: Text(label, style: theme.textTheme.bodyMedium),
              // 标出当前来源
              selected: source == current,
              onSelected: (_) {
                DisplaySettings.instance.setDataSource(source);
                Navigator.of(context).pop(source);
              },
            ),
        ],
      ),
    );
  }
}
