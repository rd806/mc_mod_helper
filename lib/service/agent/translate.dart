import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:mc_mod_helper/setting/language_settings.dart';

import '../../setting/agent_settings.dart';

/// AI 翻译服务(OpenAI 兼容的 chat/completions 接口)。
///
/// 接口地址 / API Key / 模型名由用户在设置页填写(见 AgentSettings,
/// 与模组助手共用);这里不做任何内置密钥。
/// 翻译请求把整段正文 HTML 交给模型,要求它只翻译可读文本、原样保留所有
/// 标签与属性,再对返回内容做代码围栏清理与基本校验。
///
/// 结果按「来源:标识|目标语言」做**会话内内存缓存**:同一详情重复切换
/// 原文/译文、或来回翻页都不会重复计费;重启应用后缓存失效。
class TranslateApi {
  TranslateApi._();

  /// 测试可替换的客户端工厂(与其余 Api 一致的模式)
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= clientFactory();

  /// 单次请求超时(模型翻译整篇正文可能较慢,给得宽松些)
  static const Duration _timeout = Duration(seconds: 120);

  /// 单次请求的正文预算(字符)。超过则按 HTML 顶层节点分块、
  /// 逐块翻译后拼接——早前实现是超长直接截断,长正文只翻译前半段
  static const int chunkChars = 6000;

  /// 输出上限:思考模型(如 deepseek-reasoner)会在思维链上占用输出配额,
  /// 默认上限偏小时正文译文会被截断甚至拿不到 content,这里给足空间
  static const int maxOutputTokens = 8192;

  /// 会话内缓存:key = '来源id|目标语言' → 译文 HTML
  static final Map<String, String> _cache = {};

  @visibleForTesting
  static void clearCaches() {
    _cache.clear();
    _clientInstance = null;
  }

  /// 翻译正文 HTML;命中缓存直接返回。
  ///
  /// 长正文按 HTML 顶层节点切成多块分别翻译再拼接(不截断内容):
  /// 每个块由完整的顶层节点组成,标签成对,不会被切开。
  /// [onProgress] 会在每块完成后回调 (已完成块数, 总块数),供 UI 显示进度。
  /// [cacheKey] 用于区分不同模组/来源(如 'mcmod:123')。
  /// 未配置 API Key 时抛 [TranslateNotConfiguredException]。
  static Future<String> translateHtml(
    String html, {
    required String cacheKey,
    String? targetLang,
    String? baseUrl,
    String? apiKey,
    String? model,
    void Function(int done, int total)? onProgress,
  }) async {
    final settings = LanguageSettings.instance;
    final agent = AgentSettings.instance;
    final lang = targetLang ?? settings.translateLang;
    final key = '$cacheKey|$lang';
    final cached = _cache[key];
    if (cached != null) return cached;

    final token = (apiKey ?? agent.apiKey).trim();
    if (token.isEmpty) throw const TranslateNotConfiguredException();
    final endpoint = (baseUrl ?? agent.baseUrl).trim();
    final modelName = (model ?? agent.model).trim();

    final chunks = _splitHtml(html, chunkChars);
    if (chunks.isEmpty) return html;

    final translated = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final content = await _chat(
        endpoint: endpoint,
        apiKey: token,
        model: modelName,
        prompt: _buildPrompt(chunks[i], lang),
      );
      translated.add(_cleanResult(content));
      onProgress?.call(i + 1, chunks.length);
    }
    final result = translated.join('');
    _cache[key] = result;
    return result;
  }

  /// 把正文 HTML 按顶层节点切成不超过 [budget] 字符的块。
  ///
  /// - 普通节点累积到接近预算再成块;
  /// - 单个超预算节点(如大表格)整体成块,避免标签被切成两半;
  /// - 超长纯文本节点(无标签的长段落)按句末标点/换行再切,
  ///   仍超长时按长度硬切(纯文本切分不影响结构)。
  static List<String> _splitHtml(String html, int budget) {
    final nodes = html_parser.parseFragment(html).nodes;
    final chunks = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
    }

    for (final node in nodes) {
      // Element 用源码;Text 节点重新转义(& < >),否则文本里的
      // 特殊字符在送模型/回填时会被当成标签
      final String source;
      if (node is dom.Element) {
        source = node.outerHtml;
      } else if (node is dom.Text) {
        source = _escapeText(node.text);
      } else {
        continue;
      }
      if (source.trim().isEmpty) continue;
      if (source.length >= budget) {
        flush();
        if (node is dom.Text) {
          chunks.addAll(_splitPlain(source, budget));
        } else {
          chunks.add(source); // 元素整体保留,不破坏标签结构
        }
        continue;
      }
      if (buffer.length + source.length > budget) flush();
      buffer.write(source);
    }
    flush();
    return chunks;
  }

  /// 纯文本 → HTML 源码形式(转义 & < >,保留其他字符)
  static String _escapeText(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// 纯文本按句末标点/换行切分(保留标点);无标点的超长串按长度硬切
  static List<String> _splitPlain(String text, int budget) {
    final parts = <String>[];
    var current = StringBuffer();
    for (final segment in text.split(RegExp(r'(?<=[。！？!?.\n])'))) {
      if (segment.isEmpty) continue;
      if (segment.length > budget) {
        if (current.isNotEmpty) {
          parts.add(current.toString());
          current = StringBuffer();
        }
        for (var i = 0; i < segment.length; i += budget) {
          final end = i + budget < segment.length ? i + budget : segment.length;
          parts.add(segment.substring(i, end));
        }
        continue;
      }
      if (current.length + segment.length > budget) {
        parts.add(current.toString());
        current = StringBuffer();
      }
      current.write(segment);
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts.isEmpty ? [text] : parts;
  }

  /// 该缓存是否已有对应译文(用于按钮直接切换原文/译文)
  static String? cachedHtml(String cacheKey, {String? targetLang}) {
    final lang = targetLang ?? LanguageSettings.instance.translateLang;
    return _cache['$cacheKey|$lang'];
  }

  /// 目标语言代码 → 提示词里的自然语言名
  static String langName(String code) {
    for (final (label, c) in LanguageSettings.translateLanguages) {
      if (c == code) return label;
    }
    return code;
  }

  /// 构造翻译提示词:强调保留 HTML 结构,只输出译文
  static String _buildPrompt(String html, String lang) {
    return '你是一个网页正文翻译引擎。请把下面 HTML 片段中的可读文本翻译成'
        '${langName(lang)}。\n'
        '要求:\n'
        '1. 只翻译文本内容,所有 HTML 标签、属性、链接地址、图片地址、'
        '样式与整体结构必须原样保留,不得增删标签;\n'
        '2. 代码块(<pre>/<code>)、专有名词、模组名与版本号保持原样;\n'
        '3. 直接输出翻译后的 HTML 本身,不要添加任何解释、注释或 Markdown 代码围栏。\n\n'
        'HTML:\n$html';
  }

  /// 调用 OpenAI 兼容的 chat/completions 接口,返回首个 choice 的文本
  static Future<String> _chat({
    required String endpoint,
    required String apiKey,
    required String model,
    required String prompt,
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
              // 不发送 temperature:翻译不需要随机性,而部分思考模型的
              // 兼容层会拒绝该参数(直接 400)
              'stream': false,
              'max_tokens': maxOutputTokens,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(_timeout);
    } catch (e) {
      throw Exception('翻译请求失败: $e');
    }
    if (resp.statusCode != 200) {
      throw Exception('翻译请求失败: HTTP ${resp.statusCode} ${_brief(resp.body)}');
    }
    return _extractContent(utf8.decode(resp.bodyBytes));
  }

  /// 从响应体里取出译文文本(兼容多种返回形态)。
  ///
  /// 兼容点:
  /// - 部分网关把结果包一层 `{"data": {...}}`;
  /// - `message.content` 可能是字符串,也可能是内容块数组;
  /// - 少数实现返回 completions 风格 `choices[0].text`;
  /// - 思考模型(deepseek-reasoner 等)会同时给 `reasoning_content`:
  ///   正文为空而只有思维链时,给出明确提示而非笼统的"结果为空";
  /// - `finish_reason == 'length'` 说明被输出上限截断(思考占配额时常见)。
  static String _extractContent(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw Exception('翻译结果无法解析: ${_brief(body)}');
    }
    // 解包 {"data": {...}} 形式的信封
    if (decoded is Map<String, dynamic> &&
        decoded['choices'] == null &&
        decoded['data'] is Map<String, dynamic>) {
      decoded = decoded['data'];
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('翻译结果格式异常: ${_brief(body)}');
    }
    final choices = decoded['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) throw Exception('翻译结果为空');
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) {
      throw Exception('翻译结果格式异常: ${_brief(body)}');
    }

    // message.content:字符串或内容块数组
    final message = choice['message'];
    var text = message is Map<String, dynamic>
        ? _contentToText(message['content'])
        : null;
    // 少数实现(旧 completions 风格)用 choices[0].text
    text ??= _contentToText(choice['text']);

    if (text == null || text.trim().isEmpty) {
      final reasoning = message is Map<String, dynamic>
          ? message['reasoning_content']
          : null;
      if (reasoning is String && reasoning.trim().isNotEmpty) {
        throw Exception(
          '模型只返回了思考过程(未产出译文)。若使用思考模型(如 deepseek-reasoner),'
          '请改用非思考模型,或调大该模型的输出上限',
        );
      }
      throw Exception('翻译结果为空');
    }

    if (choice['finish_reason'] == 'length') {
      throw Exception('翻译结果被输出上限截断,请缩短正文或换用输出上限更大的模型');
    }
    return text.trim();
  }

  /// content 可能是字符串,也可能是 `[{type:'text', text:'...'}]` 块数组
  static String? _contentToText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map && part['text'] is String) {
          buffer.write(part['text']);
        }
      }
      final s = buffer.toString();
      return s.isEmpty ? null : s;
    }
    return null;
  }

  /// 错误响应体截断(避免把整页 HTML 塞进异常信息)
  static String _brief(String body) {
    final s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// 清理模型输出:去掉可能的 ```html 代码围栏与前后空行
  static String _cleanResult(String text) {
    var s = text.trim();
    final fence = RegExp(
      r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```$',
      multiLine: false,
    ).firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();
    return s;
  }
}

/// 未配置 AI 接口 Key(详情页据此提示用户去设置页填写)
class TranslateNotConfiguredException implements Exception {
  const TranslateNotConfiguredException();

  @override
  String toString() => '尚未配置 AI 接口 Key,请到「设置 → AI 设置」填写';
}
