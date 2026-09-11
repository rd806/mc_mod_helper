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

/// 一个对话:一组按时间排列的消息,带自动生成的标题与更新时间
class AgentConversation {
  AgentConversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title = '',
    List<AgentChatItem> items = const [],
  }) : _items = [...items];

  /// 标识(创建时刻的微秒时间戳,足够唯一且可排序)
  final String id;

  final DateTime createdAt;

  /// 最近一次发言时间(列表按它倒序)
  DateTime updatedAt;

  /// 标题:由第一条用户消息自动生成,可空(空表示还没聊过)
  String title;

  final List<AgentChatItem> _items;

  List<AgentChatItem> get items => List.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  /// 列表里显示的标题(还没聊过的对话)
  String get displayTitle => title.isEmpty ? '新对话' : title;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'items': [for (final item in _items) item.toJson()],
  };

  /// 从存储值还原;结构不合法时返回 null(整条对话丢弃)
  static AgentConversation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final created = _time(raw['createdAt']) ?? DateTime.now();
    return AgentConversation(
      id: id,
      title: raw['title'] as String? ?? '',
      createdAt: created,
      updatedAt: _time(raw['updatedAt']) ?? created,
      items: [
        for (final e in raw['items'] as List<dynamic>? ?? const [])
          ?AgentChatItem.fromJson(e),
      ],
    );
  }

  static DateTime? _time(Object? raw) =>
      raw is num ? DateTime.fromMillisecondsSinceEpoch(raw.toInt()) : null;
}

/// 助手对话记录:单例 ChangeNotifier + shared_preferences 持久化。
///
/// 支持多个对话:每次打开助手开启新对话([startNew]),历史对话在
/// [conversations] 里可选、可删。消息本身要作为多轮上下文发给模型,
/// 又要跨会话保留,因此独立于面板的 State 存放。
/// 启动时 [load] 一次(与 SettingsService 同时,在 runApp 前)。
class AgentHistoryService extends ChangeNotifier {
  AgentHistoryService._();

  /// 全局唯一实例
  static final AgentHistoryService instance = AgentHistoryService._();

  static const String _historyKey = 'agent_history';

  /// 单个对话保留的消息条数上限(超出丢弃最早的;避免无限增长)
  static const int maxItems = 100;

  /// 保留的对话数量上限(超出丢弃最旧的)
  static const int maxConversations = 50;

  /// 自动标题的最大字数
  static const int titleChars = 20;

  /// 全部对话(最近更新的在前)
  List<AgentConversation> _conversations = [];
  String? _currentId;

  /// 同一时刻建多个对话时的序号后缀(系统时钟精度内可能取到相同的时间戳)
  int _seq = 0;

  /// 生成对话 id:创建时刻,必要时加序号后缀保证唯一。
  /// 只用时间戳会撞车——同一微秒内建的两个对话 id 相同,
  /// 之后删除其中一个会把两个一起删掉
  String _createId(DateTime now) {
    final base = '${now.microsecondsSinceEpoch}';
    var id = base;
    while (_conversations.any((c) => c.id == id)) {
      id = '$base-${++_seq}';
    }
    return id;
  }

  List<AgentConversation> get conversations =>
      List.unmodifiable(_conversations);

  String? get currentId => _currentId;

  /// 当前对话(没有则为 null)
  AgentConversation? get current {
    final id = _currentId;
    if (id == null) return null;
    for (final conversation in _conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  /// 当前对话的消息(面板渲染用)
  List<AgentChatItem> get items => current?.items ?? const [];

  bool get isEmpty => items.isEmpty;

  /// 开启一个新对话并切过去。
  ///
  /// 当前对话已经是空的时候直接复用:反复开关面板不该堆一串空对话
  AgentConversation startNew() {
    final existing = current;
    if (existing != null && existing.isEmpty) return existing;
    final now = DateTime.now();
    final conversation = AgentConversation(
      id: _createId(now),
      createdAt: now,
      updatedAt: now,
    );
    _conversations.insert(0, conversation);
    _currentId = conversation.id;
    _trim();
    notifyListeners();
    _persist();
    return conversation;
  }

  /// 切换到某个历史对话
  void select(String id) {
    if (_currentId == id || !_conversations.any((c) => c.id == id)) return;
    _currentId = id;
    notifyListeners();
    _persist();
  }

  /// 删除某个对话;删的是当前对话时落到最近的一个上
  Future<void> delete(String id) async {
    final before = _conversations.length;
    _conversations.removeWhere((c) => c.id == id);
    if (_conversations.length == before) return;
    if (_currentId == id) {
      _currentId = _conversations.isEmpty ? null : _conversations.first.id;
    }
    notifyListeners();
    await _persist();
  }

  /// 读取已保存的对话(每次调用都从存储重新读取,内容被外部清空时随之复位;
  /// 与 SettingsService.load 一样,测试里可用空 mock 存储把单例重置)
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      final data = (raw == null || raw.isEmpty) ? null : jsonDecode(raw);
      _conversations = [];
      _currentId = null;
      if (data is Map<String, dynamic>) {
        for (final e in data['conversations'] as List<dynamic>? ?? const []) {
          final conversation = AgentConversation.fromJson(e);
          if (conversation != null) _conversations.add(conversation);
        }
        _currentId = data['current'] as String?;
      } else if (data is List) {
        // 旧存档(单一对话的扁平消息列表)迁移成一个对话
        final items = [for (final e in data) ?AgentChatItem.fromJson(e)];
        if (items.isNotEmpty) {
          final time = DateTime.now();
          _conversations.add(
            AgentConversation(
              id: _createId(time),
              createdAt: time,
              updatedAt: time,
              title: _titleFrom(
                items
                    .firstWhere((i) => i.fromUser, orElse: () => items.first)
                    .text,
              ),
              items: items,
            ),
          );
        }
      }
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _trim();
      // 当前对话失效(被删或存档异常)时落到最近的一个
      if (!_conversations.any((c) => c.id == _currentId)) {
        _currentId = _conversations.isEmpty ? null : _conversations.first.id;
      }
    } catch (_) {
      // 读取/解析失败:当作没有历史,不阻塞启动
      _conversations = [];
      _currentId = null;
    }
    notifyListeners();
  }

  /// 往当前对话追加一条消息(先更新内存让界面立即显示,再异步写盘)
  Future<void> add(AgentChatItem item) async {
    final conversation = current ?? startNew();
    conversation._items.add(item);
    if (conversation._items.length > maxItems) {
      conversation._items.removeRange(0, conversation._items.length - maxItems);
    }
    // 首条用户消息作为标题(助手回复或快捷指令不参与)
    if (conversation.title.isEmpty && item.fromUser) {
      conversation.title = _titleFrom(item.text);
    }
    conversation.updatedAt = DateTime.now();
    // 最近使用的排到最前
    _conversations.remove(conversation);
    _conversations.insert(0, conversation);
    _trim();
    notifyListeners();
    await _persist();
  }

  /// 由首条用户消息生成标题(压平空白并截断)
  static String _titleFrom(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > titleChars ? '${t.substring(0, titleChars)}…' : t;
  }

  /// 对话数量超上限时丢弃最旧的(当前对话始终保留)
  void _trim() {
    if (_conversations.length <= maxConversations) return;
    final kept = _conversations.take(maxConversations).toList();
    final current = this.current;
    if (current != null && !kept.contains(current)) {
      kept[kept.length - 1] = current;
    }
    _conversations = kept;
  }

  /// 清空当前对话的消息(对话本身保留,面板的「清空当前对话」按钮调用)
  Future<void> clear() async {
    final conversation = current;
    if (conversation == null || conversation.isEmpty) return;
    conversation._items.clear();
    conversation.title = '';
    conversation.updatedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// 异步写盘;失败不影响本次会话的内存记录
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode({
          'current': _currentId,
          'conversations': [
            for (final conversation in _conversations) conversation.toJson(),
          ],
        }),
      );
    } catch (_) {
      // 忽略写盘失败
    }
  }
}
