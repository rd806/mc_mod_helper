import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../model/author.dart';
import '../../model/mod/mod_detail.dart';
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

/// 详情页上下文:把当前正在浏览的模组资料交给助手,
/// 用于「总结模组内容」与「推荐相似模组」。
///
/// 正文 HTML 在这里就转成纯文本并截断(模型上下文有限,
/// 摘要也只需要正文内容,不需要标签)。
class AgentModContext {
  const AgentModContext({
    required this.id,
    required this.source,
    required this.title,
    this.subName,
    this.description,
    this.body,
    this.authors = const [],
    this.platform,
    this.mcVersions = const {},
  });

  /// 从详情构造(正文去标签转纯文本)
  factory AgentModContext.fromDetail(ModDetail detail) => AgentModContext(
    id: detail.id,
    source: detail.source,
    title: detail.title,
    subName: detail.subName,
    description: detail.description,
    body: _plainText(detail.body ?? ''),
    authors: [for (final a in detail.authors ?? const <Author>[]) a.name],
    platform: detail.platform,
    mcVersions: detail.mcVersions,
  );

  /// 统一模组标识(与 ModSummary.id 一致)
  final String id;

  /// 数据来源
  final ModSource source;

  final String title;
  final String? subName;
  final String? description;

  /// 正文纯文本(超长时已截断)
  final String? body;

  final List<String> authors;
  final String? platform;
  final Map<String, List<String>> mcVersions;

  /// 正文最多交给模型多少字符
  static const int maxBodyChars = 6000;

  /// 每个加载器最多列出多少个版本
  static const int maxVersionsPerLoader = 6;

  /// 去重键「来源:标识」(与搜索去重一致),用于把当前模组排除出候选
  String get key => '${source.name}:$id';

  /// 资料块:拼进系统提示,作为模型回答"总结/相似推荐"的依据
  String toPromptText() {
    final buffer = StringBuffer()..writeln('标题:$title');
    if (subName != null && subName!.isNotEmpty) {
      buffer.writeln('英文名:$subName');
    }
    if (description != null && description!.isNotEmpty) {
      buffer.writeln('简介:$description');
    }
    if (authors.isNotEmpty) buffer.writeln('作者:${authors.join('、')}');
    if (platform != null && platform!.isNotEmpty) {
      buffer.writeln('支持平台:$platform');
    }
    if (mcVersions.isNotEmpty) {
      final versions = [
        for (final entry in mcVersions.entries)
          '${entry.key} ${entry.value.take(maxVersionsPerLoader).join('/')}',
      ];
      buffer.writeln('支持版本:${versions.join(';')}');
    }
    final text = body;
    if (text != null && text.isNotEmpty) buffer.writeln('正文:\n$text');
    return buffer.toString().trim();
  }

  /// HTML → 纯文本:去掉 script/style、取全部文本、压缩空白、超长截断
  static String _plainText(String html) {
    if (html.isEmpty) return '';
    String text;
    try {
      final doc = html_parser.parse(html);
      for (final node in doc.querySelectorAll('script, style')) {
        node.remove();
      }
      text = doc.documentElement?.text ?? '';
    } catch (_) {
      // 解析失败(极端畸形 HTML):退回未去标签的原文
      text = html;
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > maxBodyChars
        ? '${text.substring(0, maxBodyChars)}…'
        : text;
  }
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
  /// [mod] 为详情页带过来的当前模组资料:带上它助手就能总结该模组或推荐
  /// 相似模组,并会把这个模组本身排除出候选(不推荐它自己)。
  /// 未配置 API Key 时抛 [AgentNotConfiguredException]。
  static Future<AgentReply> ask(
    List<AgentMessage> history, {
    AgentModContext? mod,
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
        {'role': 'system', 'content': _systemContent(mod)},
        for (final m in history)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
      ],
    );

    final parsed = _parseReply(content);
    final keywords = parsed.$2;
    if (keywords.isEmpty) {
      return AgentReply(text: parsed.$1);
    }
    final mods = await _search(keywords, exclude: mod?.key);
    return AgentReply(text: parsed.$1, mods: mods);
  }

  /// 系统提示:约束输出为 JSON 并给出搜索词要求;
  /// 有模组上下文时在末尾附上资料(放在规则之后,不干扰格式要求)
  static String _systemContent(AgentModContext? mod) {
    if (mod == null) return _systemPrompt;
    return '$_systemPrompt\n\n'
        '当前用户正在浏览的模组资料(总结或推荐相似模组只依据这些内容,'
        '资料里没写的不要编造):\n${mod.toPromptText()}';
  }

  /// 系统提示:约束输出为 JSON,并给出搜索词撰写要求
  static const String _systemPrompt =
      '你是「MC Mod Helper」应用内的 Minecraft 模组助手,能帮用户找模组、'
      '总结当前浏览的模组、以及推荐相似的模组。\n'
      '规则:\n'
      '1. 如果用户在找模组:用一句简短中文回复,并在 search 里给出 1~$maxKeywords 个'
      '用于站内搜索的关键词——优先模组中文名、英文名或常见缩写(如 "JEI"、"匠魂"、"优化"),'
      '不要放整句话、不要放解释;\n'
      '2. 如果用户要你总结/介绍某个模组(下面附有该模组资料时):用一段简短中文'
      '(不超过 150 字)概括它的用途、主要功能与适用场景,只依据资料、不要编造,'
      'search 留空数组;\n'
      '3. 如果用户要你推荐相似模组:用一句话说明推荐方向,并在 search 里给出 '
      '1~$maxKeywords 个同类模组的搜索关键词(类别词或知名同类模组名,'
      '如 "优化"、"科技"、"JEI"),不要放当前模组自己;\n'
      '4. 如果用户只是闲聊或问题不适合搜索:search 留空数组,正常回答即可;\n'
      '5. 只输出一个 JSON 对象,不要任何额外文字或 Markdown 代码围栏,格式为:\n'
      '{"reply": "给用户看的一句话", "search": ["关键词"]}';

  /// 依次用各关键词搜索并合并去重(单个关键词失败不影响整体)。
  /// [exclude] 是「来源:标识」,命中即跳过(详情页不推荐当前模组自己)
  static Future<List<ModSummary>> _search(
    List<String> keywords, {
    String? exclude,
  }) async {
    final source = SettingsService.instance.dataSource;
    final mods = <ModSummary>[];
    final seen = <String>{};
    for (final keyword in keywords) {
      try {
        for (final mod in await SourceManager.getSearch(source, keyword)) {
          final key = '${mod.source.name}:${mod.id}';
          if (key == exclude) continue;
          if (seen.add(key)) mods.add(mod);
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
