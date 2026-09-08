import 'package:flutter/material.dart';

import '../../../model/mod/mod_detail.dart';
import '../intro/section_title.dart';

/// 加载环境:environment 为 [客户端需求, 服务端需求] 的枚举值列表,
/// 有时只有一侧(mcmod),按实际元素数量显示
class EnvironmentCard extends StatelessWidget {
  const EnvironmentCard({super.key, required this.mod});

  final ModDetail mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final env = mod.environment;
    if (env == null || env.isEmpty) return const SizedBox.shrink();
    // 首元素(客户端)必然存在;服务端可能缺位(mcmod 有时只标一侧)
    final client = _getInfo(env[0]);
    final server = env.length > 1 ? _getInfo(env[1]) : null;
    // 收集所有有效的 Chip
    // 使用 Wrap 实现响应式布局
    final List<Widget> chips = [];
    if (client != null) {
      chips.add(
        Chip(
          avatar: Icon(Icons.computer_rounded, size: 18),
          visualDensity: VisualDensity.standard,
          label: Text('客户端：$client', style: theme.textTheme.labelMedium),
        ),
      );
    }
    if (server != null) {
      chips.add(
        Chip(
          avatar: Icon(Icons.storage_rounded, size: 18),
          visualDensity: VisualDensity.standard,
          label: Text('服务端：$server', style: theme.textTheme.labelMedium),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DetailSectionTitle(
              title: '加载环境',
              icon: Icons.construction_rounded,
            ),
            Wrap(
              spacing: 8.0, // 水平间距
              runSpacing: 8.0, // 垂直间距（换行时）
              children: chips,
            ),
          ],
        ),
      ),
    );
  }

  /// 环境枚举值 → 展示文字
  String? _getInfo(String s) {
    switch (s) {
      case 'required':
        return '必需';
      case 'optional':
        return '可选';
      case 'unsupported':
        return '无效';
      default:
        return '未知';
    }
  }
}
