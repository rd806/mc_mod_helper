import 'package:flutter/material.dart';

import '../../model/mod/mod_summary.dart';
import '../../page/more/description.dart';
import '../../service/agent/agent.dart';
import '../../service/agent/history.dart';
import '../../icon/link_icons.dart';

/// 打开模组助手对话面板(底部弹出)。
///
/// [mod] 由详情页传入:带上它面板会多出「总结这个模组」「推荐相似模组」
/// 两个快捷指令,并把该模组资料一并交给模型。
Future<void> showAgentSheet(BuildContext context, {AgentModContext? mod}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AgentSheet(mod: mod),
  );
}

/// 对话面板:输入想找的模组描述 → AI 给出搜索词 → 站内搜索 → 候选卡片。
///
/// 候选卡片点击后在应用内打开模组详情页(关闭面板再跳转)。
class AgentSheet extends StatefulWidget {
  const AgentSheet({super.key, this.mod});

  /// 当前浏览的模组(详情页打开时传入;为空则是通用助手)
  final AgentModContext? mod;

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  /// 快捷指令(有模组上下文时展示,点击即发送)
  static const String summarizePrompt = '总结这个模组的内容';
  static const String similarPrompt = '推荐与它相似的模组';

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;

  /// 面板正显示历史对话列表(而不是消息列表)
  bool _showHistory = false;

  /// 对话记录由服务持有(多对话 + 持久化);
  /// 服务变化时重建面板
  AgentHistoryService get _history => AgentHistoryService.instance;

  /// 当前对话的消息
  List<AgentChatItem> get _items => _history.items;

  @override
  void initState() {
    super.initState();
    _history.addListener(_onHistoryChanged);
    // 每次打开助手都开一个新对话(当前已是空对话时复用,不堆空对话)
    _history.startNew();
    // 有历史消息时,打开面板直接停在最新一条
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

  /// 发送一条消息。[preset] 为快捷指令(直接发送,不经过输入框)
  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _loading) return;
    if (preset == null) _input.clear();
    setState(() => _loading = true);
    await AgentHistoryService.instance.add(AgentChatItem.user(text));
    _scrollToBottom();
    try {
      // 历史由服务持久化持有,请求本身无状态
      final history = [
        for (final item in _items)
          AgentMessage(fromUser: item.fromUser, text: item.text),
      ];
      // 详情页打开时带上当前模组资料,助手才能总结/推荐相似
      final reply = await AgentApi.ask(history, mod: widget.mod);
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

  /// 清空当前对话的消息(先确认,清空后不可恢复)
  Future<void> _confirmClear() async {
    final ok = await _confirm(
      title: '清空当前对话',
      content: '将删除本对话的全部消息与候选模组,且无法恢复。',
      action: '清空',
    );
    if (!ok) return;
    await _history.clear();
  }

  /// 删除某个历史对话(含其全部消息)
  Future<void> _confirmDelete(AgentConversation conversation) async {
    final ok = await _confirm(
      title: '删除对话',
      content: '将删除「${conversation.displayTitle}」的全部消息,且无法恢复。',
      action: '删除',
    );
    if (!ok) return;
    await _history.delete(conversation.id);
  }

  /// 二次确认对话框
  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 切到某个历史对话
  void _openConversation(AgentConversation conversation) {
    _history.select(conversation.id);
    setState(() => _showHistory = false);
    _scrollToBottom(animate: false);
  }

  /// 新建对话并回到消息列表
  void _newConversation() {
    _history.startNew();
    setState(() => _showHistory = false);
    _scrollToBottom(animate: false);
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
              child: _showHistory
                  ? _buildConversationList(theme)
                  : _items.isEmpty
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
            // 详情页打开的助手:总结 / 推荐相似 两个快捷指令
            if (widget.mod != null) _buildQuickActions(theme),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // 历史列表模式:返回 + 标题 + 新建对话
    if (_showHistory) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 8, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _showHistory = false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '历史对话',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _newConversation,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建对话'),
            ),
          ],
        ),
      );
    }
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
            tooltip: '历史对话',
            icon: const Icon(Icons.history),
            onPressed: () => setState(() => _showHistory = true),
          ),
          IconButton(
            tooltip: '清空当前对话',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
    );
  }

  /// 历史对话列表:标题(首条用户消息)+ 消息数/时间,可切换或删除
  Widget _buildConversationList(ThemeData theme) {
    final conversations = _history.conversations;
    if (conversations.isEmpty) {
      return Center(
        child: Text(
          '还没有历史对话',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: conversations.length,
      itemBuilder: (context, i) {
        final conversation = conversations[i];
        final selected = conversation.id == _history.currentId;
        return ListTile(
          dense: true,
          selected: selected,
          leading: Icon(
            selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
            color: selected ? theme.colorScheme.primary : null,
          ),
          title: Text(
            conversation.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${conversation.length} 条 · ${_formatTime(conversation.updatedAt)}',
          ),
          trailing: IconButton(
            tooltip: '删除对话',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(conversation),
          ),
          onTap: () => _openConversation(conversation),
        );
      },
    );
  }

  /// 列表里的时间:今天显示时刻,更早显示日期
  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!time.isBefore(today)) {
      final hh = time.hour.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return '${time.month}月${time.day}日';
  }

  Widget _buildEmpty(ThemeData theme) {
    final mod = widget.mod;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          mod == null
              ? '描述你想找的模组,例如:\n“能查看物品合成配方的模组”\n“有没有优化游戏帧数的模组?”'
              : '正在浏览「${mod.title}」\n可以让我总结它的内容,或者推荐相似的模组',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 快捷指令:有模组上下文时显示在输入区上方,点一下直接发问
  Widget _buildQuickActions(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.summarize_outlined, size: 18),
            label: const Text('总结这个模组'),
            onPressed: () => _send(preset: summarizePrompt),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.recommend_outlined, size: 18),
            label: const Text('推荐相似模组'),
            onPressed: () => _send(preset: similarPrompt),
          ),
        ],
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
                hintText: widget.mod == null ? '描述你想找的模组…' : '问问关于这个模组的…',
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
