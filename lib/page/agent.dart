import 'package:flutter/material.dart';
import 'package:mc_mod_helper/widget/handler/agent_sheet.dart';

/// 模组助手
class AgentPage extends StatelessWidget {
  const AgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MC Mod Helper')),
      body: AgentSheet(),
    );
  }
}
