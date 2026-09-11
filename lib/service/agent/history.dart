import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/mod/mod_summary.dart';
import '../value/source.dart';

/// 助手对话里的一条消息(用户文本,或助手文本 + 候选模组)。
///
/// 候选模组只存跳详情与卡片渲染所需的摘要字段
/// (id/title/description/source/subName/iconUrl),
/// 统计信息等详情数据体量大且可重新拉取,不入库。
class AgentChatItem {
  const AgentChatItem({
    required this.fromUser,
    required this.text,
    this.mods = const [],
  });

  /// 用户发言
  factory AgentChatItem.user(String text) =>
      AgentChatItem(fromUser: true, text: text);

  /// 助手回复([mods] 为空表示纯聊天)
  factory AgentChatItem.assistant(
    String text, {
    List<ModSummary> mods = const [],
  }) => AgentChatItem(fromUser: false, text: text, mods: mods);

  final bool fromUser;
  final String text;
  final List<ModSummary> mods;

  Map<String, Object?> toJson() => {
    'fromUser': fromUser,
    'text': text,
    'mods': [for (final mod in mods) _modToJson(mod)],
  };

  /// 从存储值还原;结构不合法时返回 null(整条消息丢弃,不影响其余记录)
  static AgentChatItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String) return null;
    return AgentChatItem(
      fromUser: raw['fromUser'] == true,
      text: text,
      mods: [
        for (final e in raw['mods'] as List<dynamic>? ?? const [])
          ?_modFromJson(e),
      ],
    );
  }

  static Map<String, Object?> _modToJson(ModSummary mod) => {
    'id': mod.id,
    'title': mod.title,
    'description': mod.description,
    'source': mod.source.name,
    'subName': mod.subName,
    'iconUrl': mod.iconUrl,
  };

  static ModSummary? _modFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    return ModSummary(
      id: id,
      title: title,
      description: raw['description'] as String? ?? '',
      subName: raw['subName'] as String?,
      iconUrl: raw['iconUrl'] as String?,
      source: SourceManager.sourceToString(raw['source'] as String?),
    );
  }
}

/// 助手对话记录:单例 ChangeNotifier + shared_preferences 持久化。
///
/// 对话消息本身要作为多轮上下文发给模型,又需要跨会话保留
/// (关掉面板/重启应用后接着聊),因此独立于面板的 State 存放。
/// 启动时 [load] 一次(与 SettingsService 同时,在 runApp 前)。
class AgentHistoryService extends ChangeNotifier {
  AgentHistoryService._();

  /// 全局唯一实例
  static final AgentHistoryService instance = AgentHistoryService._();

  static const String _historyKey = 'agent_history';

  /// 保留的消息条数上限(超出丢弃最早的;避免无限增长)
  static const int maxItems = 100;

  List<AgentChatItem> _items = [];

  /// 全部对话消息(按时间顺序)
  List<AgentChatItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// 读取已保存的对话(每次调用都从存储重新读取,内容被外部清空时随之复位;
  /// 与 SettingsService.load 一样,测试里可用空 mock 存储把单例重置)
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) {
        _items = [];
      } else {
        final decoded = jsonDecode(raw);
        _items = decoded is List
            ? [for (final e in decoded) ?AgentChatItem.fromJson(e)]
            : <AgentChatItem>[];
      }
    } catch (_) {
      // 读取/解析失败:当作没有历史,不阻塞启动
      _items = [];
    }
    notifyListeners();
  }

  /// 追加一条消息(先更新内存让界面立即显示,再异步写盘)
  Future<void> add(AgentChatItem item) async {
    _items = [..._items, item];
    if (_items.length > maxItems) {
      _items = _items.sublist(_items.length - maxItems);
    }
    notifyListeners();
    await _persist();
  }

  /// 清空对话(面板的「清空对话」按钮调用)
  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items = [];
    notifyListeners();
    await _persist();
  }

  /// 异步写盘;失败不影响本次会话的内存记录
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode([for (final item in _items) item.toJson()]),
      );
    } catch (_) {
      // 忽略写盘失败
    }
  }
}
