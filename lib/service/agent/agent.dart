import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../model/mod/mod_summary.dart';
import '../../setting/agent_settings.dart';
import '../../setting/settings.dart';
import '../value/source.dart';

/// 一轮对话消息(面板持有历史,服务不存状态,便于测试)
class AgentMessage {
  const AgentMessage({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// 助手回复:一句话 + 候选模组(候选为空表示纯聊天)
class AgentReply {
  const AgentReply({required this.text, this.mods = const []});

  final String text;
  final List<ModSummary> mods;
}

/// 模组助手(agent):把用户的自然语言描述变成站内搜索,返回候选模组。
///
/// 与 AI 翻译复用同一套 OpenAI 兼容配置(见 AgentSettings:接口地址 / Key / 模型)。
/// 协议:让模型只输出一个 JSON 对象
/// `{"reply": "给用户的话", "search": ["搜索词", ...]}`,
/// 客户端取出搜索词后调用现有搜索接口,把结果作为候选卡片交给界面。
///
/// 采用"提示词 + JSON"而不是 function calling:兼容性更好
/// (部分网关/思考模型对 tools 支持不一),解析失败时按纯文本回复兜底。
class AgentApi {
  AgentApi._();

  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= clientFactory();

  static const Duration _timeout = Duration(seconds: 60);

  /// 单次最多使用的搜索词数量(避免过多请求)
  static const int maxKeywords = 3;

  /// 候选模组数量上限
  static const int maxCandidates = 8;

  @visibleForTesting
  static void clearCaches() {
    _clientInstance = null;
  }

  /// 让助手回答一轮;history 为完整对话(含本轮用户消息)。
  ///
  /// 未配置 API Key 时抛 [AgentNotConfiguredException]。
  static Future<AgentReply> ask(
    List<AgentMessage> history, {
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    final agent = AgentSettings.instance;
    final token = (apiKey ?? agent.apiKey).trim();
    if (token.isEmpty) throw const AgentNotConfiguredException();
    final endpoint = (baseUrl ?? agent.baseUrl).trim();
    final modelName = (model ?? agent.model).trim();

    final content = await _chat(
      endpoint: endpoint,
      apiKey: token,
      model: modelName,
      messages: [
        {'role': 'system', 'content': _systemPrompt},
        for (final m in history)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
      ],
    );

    final parsed = _parseReply(content);
    final keywords = parsed.$2;
    if (keywords.isEmpty) {
      return AgentReply(text: parsed.$1);
    }
    final mods = await _search(keywords);
    return AgentReply(text: parsed.$1, mods: mods);
  }

  /// 系统提示:约束输出为 JSON,并给出搜索词撰写要求
  static const String _systemPrompt =
      '你是「MC Mod Helper」应用内的 Minecraft 模组助手,帮用户从自然语言描述里找到想看的模组。\n'
      '规则:\n'
      '1. 如果用户在找模组:用一句简短中文回复,并在 search 里给出 1~$maxKeywords 个'
      '用于站内搜索的关键词——优先模组中文名、英文名或常见缩写(如 "JEI"、"匠魂"、"优化"),'
      '不要放整句话、不要放解释;\n'
      '2. 如果用户只是闲聊或问题不适合搜索:search 留空数组,正常回答即可;\n'
      '3. 只输出一个 JSON 对象,不要任何额外文字或 Markdown 代码围栏,格式为:\n'
      '{"reply": "给用户看的一句话", "search": ["关键词"]}';

  /// 依次用各关键词搜索并合并去重(单个关键词失败不影响整体)
  static Future<List<ModSummary>> _search(List<String> keywords) async {
    final source = SettingsService.instance.dataSource;
    final mods = <ModSummary>[];
    final seen = <String>{};
    for (final keyword in keywords) {
      try {
        for (final mod in await SourceManager.getSearch(source, keyword)) {
          if (seen.add('${mod.source.name}:${mod.id}')) mods.add(mod);
          if (mods.length >= maxCandidates) return mods;
        }
      } catch (_) {
        // 单次搜索失败(网络/限流)忽略,其它关键词继续
      }
    }
    return mods;
  }

  /// 解析模型输出 → (回复文本, 搜索词列表)。
  ///
  /// 容忍代码围栏与前后多余文字;完全解析不出 JSON 时,
  /// 把整段输出当作纯文本回复(不影响正常聊天)。
  static (String, List<String>) _parseReply(String raw) {
    final text = _stripFence(raw.trim());
    final jsonText = _extractJsonObject(text);
    if (jsonText != null) {
      try {
        final data = jsonDecode(jsonText);
        if (data is Map<String, dynamic>) {
          final reply = (data['reply'] as String?)?.trim() ?? '';
          final search = (data['search'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(maxKeywords)
              .toList();
          return (reply.isEmpty ? text : reply, search);
        }
      } catch (_) {
        // 落到下面的纯文本兜底
      }
    }
    return (text, const <String>[]);
  }

  /// 取第一个 `{` 到最后一个 `}` 之间的内容(容忍模型在 JSON 前后多说话)
  static String? _extractJsonObject(String text) {
    if (text.startsWith('{') && text.endsWith('}')) return text;
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) return text.substring(start, end + 1);
    return null;
  }

  /// 去掉可能的 ```json 代码围栏
  static String _stripFence(String text) {
    final match = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```$')
        .firstMatch(text);
    return match == null ? text : match.group(1)!.trim();
  }

  /// 调用 OpenAI 兼容接口,返回首个 choice 的文本内容
  static Future<String> _chat({
    required String endpoint,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final uri = Uri.parse(
      endpoint.endsWith('/')
          ? '${endpoint}chat/completions'
          : '$endpoint/chat/completions',
    );
    late final http.Response resp;
    try {
      resp = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'stream': false,
              'messages': messages,
            }),
          )
          .timeout(_timeout);
    } catch (e) {
      throw Exception('助手请求失败: $e');
    }
    if (resp.statusCode != 200) {
      throw Exception('助手请求失败: HTTP ${resp.statusCode} ${_brief(resp.body)}');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    final data =
        decoded is Map<String, dynamic> &&
            decoded['choices'] == null &&
            decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : decoded as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) throw Exception('助手没有返回内容');
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    final text = content is String ? content : _contentPartsText(content);
    if (text == null || text.trim().isEmpty) {
      throw Exception('助手没有返回内容');
    }
    return text;
  }

  static String? _contentPartsText(dynamic content) {
    if (content is! List) return null;
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is Map && part['text'] is String) buffer.write(part['text']);
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }

  static String _brief(String body) {
    final s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

/// 未配置 AI 接口 Key(助手面板据此提示去设置页填写)
class AgentNotConfiguredException implements Exception {
  const AgentNotConfiguredException();

  @override
  String toString() => '尚未配置 AI 接口 Key,请到「设置 → AI 设置」填写';
}
