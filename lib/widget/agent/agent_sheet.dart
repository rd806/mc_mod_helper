import 'package:flutter/material.dart';

import '../../model/mod/mod_summary.dart';
import '../../page/more/description.dart';
import '../../service/agent/agent.dart';
import '../../service/agent/history.dart';
import '../common/link_icons.dart';

/// 打开模组助手对话面板(底部弹出)
Future<void> showAgentSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AgentSheet(),
  );
}

/// 对话面板:输入想找的模组描述 → AI 给出搜索词 → 站内搜索 → 候选卡片。
///
/// 候选卡片点击后在应用内打开模组详情页(关闭面板再跳转)。
class AgentSheet extends StatefulWidget {
  const AgentSheet({super.key});

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;

  /// 对话记录由服务持有(持久化,关掉面板/重启后接着聊);
  /// 服务变化时重建面板
  List<AgentChatItem> get _items => AgentHistoryService.instance.items;

  @override
  void initState() {
    super.initState();
    AgentHistoryService.instance.addListener(_onHistoryChanged);
    // 有历史记录时,打开面板直接停在最新一条
    _scrollToBottom(animate: false);
  }

  @override
  void dispose() {
    AgentHistoryService.instance.removeListener(_onHistoryChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    _input.clear();
    setState(() => _loading = true);
    await AgentHistoryService.instance.add(AgentChatItem.user(text));
    _scrollToBottom();
    try {
      // 历史由服务持久化持有,请求本身无状态
      final history = [
        for (final item in _items)
          AgentMessage(fromUser: item.fromUser, text: item.text),
      ];
      final reply = await AgentApi.ask(history);
      if (!mounted) return;
      setState(() => _loading = false);
      await AgentHistoryService.instance.add(
        AgentChatItem.assistant(reply.text, mods: reply.mods),
      );
    } on AgentNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await AgentHistoryService.instance.add(AgentChatItem.assistant('$e'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await AgentHistoryService.instance.add(AgentChatItem.assistant('出错了:$e'));
    }
    _scrollToBottom();
  }

  /// 清空对话(先确认,清空后不可恢复)
  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('将删除全部对话记录与候选模组,且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AgentHistoryService.instance.clear();
  }

  /// 滚到最新一条;[animate] 为 false 用于打开面板时的直接定位
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 候选卡片点击:关闭面板并在应用内打开详情页
  void _openMod(ModSummary mod) {
    final navigator = Navigator.of(context);
    navigator.pop(); // 先收起面板
    navigator.push(
      MaterialPageRoute(
        builder: (_) => DetailPage(
          id: mod.id,
          source: mod.source,
          initialTitle: mod.title,
          initialDescription: mod.description,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // 键盘弹出时抬高输入区
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            _buildHeader(theme),
            const Divider(height: 1),
            Expanded(
              child: _items.isEmpty
                  ? _buildEmpty(theme)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (context, i) => _buildItem(theme, _items[i]),
                    ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '模组助手',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty ? null : _confirmClear,
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '描述你想找的模组,例如:\n“能查看物品合成配方的模组”\n“有没有优化游戏帧数的模组?”',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildItem(ThemeData theme, AgentChatItem item) {
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: item.fromUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(item.text, style: theme.textTheme.bodyMedium),
    );
    return Column(
      crossAxisAlignment: item.fromUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        bubble,
        // 候选模组卡片(总是展示,由用户点选进入详情)
        for (final mod in item.mods) _buildModTile(theme, mod),
      ],
    );
  }

  Widget _buildModTile(ThemeData theme, ModSummary mod) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          leading: LinkIcons.getIconForDataSource(mod.source),
          title: Text(mod.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: mod.description.isEmpty
              ? null
              : Text(
                  mod.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openMod(mod),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                hintText: '描述你想找的模组…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '发送',
            onPressed: _loading ? null : _send,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
