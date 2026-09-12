import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/source.dart';

import 'feature_list_page.dart';

/// 最新编辑版块的全部模组(首页「查看更多」入口)
class LastEditModPage extends StatelessWidget {
  const LastEditModPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const FeatureListPage(source: FeatureSource.lastEditTime, title: '最新编辑');
}
