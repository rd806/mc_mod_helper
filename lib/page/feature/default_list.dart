import 'package:flutter/material.dart';
import 'package:mc_mod_helper/service/value/source.dart';

import 'feature_list_page.dart';

/// 默认排序版块的全部模组(首页「查看更多」入口)
class DefaultModPage extends StatelessWidget {
  const DefaultModPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const FeatureListPage(source: FeatureSource.none, title: '默认排序');
}
