import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 接口配置(OpenAI 兼容):详情页翻译与模组助手共用同一套地址 / Key / 模型。
///
/// 单例 ChangeNotifier + shared_preferences 持久化,启动时 [load] 一次。
/// 与 [SettingsService] 分开:主题/字体这类界面设置与 AI 接口无关,
/// 拆开后互不牵连;翻译的目标语言(见 SettingsService.translateLang)
/// 属于翻译专有偏好,不放在这里。
class AgentSettings extends ChangeNotifier {
  AgentSettings._();

  /// 全局唯一实例
  static final AgentSettings instance = AgentSettings._();

  /// 配置键名
  static const String _baseUrlKey = 'agent_base_url';
  static const String _apiKeyKey = 'agent_api_key';
  static const String _modelKey = 'agent_model';

  /// 默认配置(OpenAI 官方;可改成任意 OpenAI 兼容网关,如 DeepSeek)
  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';

  String _baseUrl = defaultBaseUrl;
  String _apiKey = '';
  String _model = defaultModel;

  /// 接口地址(允许存空串表示用默认,读取时回落到 [defaultBaseUrl])
  String get baseUrl => _baseUrl.isEmpty ? defaultBaseUrl : _baseUrl;

  /// API key
  String get apiKey => _apiKey;

  /// 模型名(允许存空串表示用默认,读取时回落到 [defaultModel])
  String get model => _model.isEmpty ? defaultModel : _model;

  /// 已配置 API Key(未配置时翻译/助手给出引导提示)
  bool get configured => _apiKey.trim().isNotEmpty;

  /// 启动时读取已保存的配置(在 runApp 前调用,避免首帧用到默认值)。
  ///
  /// 每个键缺失时都显式回落到默认值(而非保持内存现值),
  /// 因此测试里可以用 setMockInitialValues({}) + load() 把单例重置。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = prefs.getString(_baseUrlKey)?.trim();
      _baseUrl = (base == null || base.isEmpty) ? defaultBaseUrl : base;
      _apiKey = prefs.getString(_apiKeyKey) ?? '';
      final model = prefs.getString(_modelKey)?.trim();
      _model = (model == null || model.isEmpty) ? defaultModel : model;
      notifyListeners();
    } catch (_) {
      // 读取失败:保持默认值,不阻塞启动
    }
  }

  /// 接口地址(允许清空表示用默认;同值短路)
  void setBaseUrl(String url) {
    final v = url.trim();
    if (v == _baseUrl) return;
    _baseUrl = v;
    notifyListeners();
    _persist(_baseUrlKey, v);
  }

  /// API Key(允许清空以关闭 AI 功能;同值短路)
  void setApiKey(String key) {
    final v = key.trim();
    if (v == _apiKey) return;
    _apiKey = v;
    notifyListeners();
    _persist(_apiKeyKey, v);
  }

  /// 模型名(允许清空表示用默认;同值短路)
  void setModel(String model) {
    final v = model.trim();
    if (v == _model) return;
    _model = v;
    notifyListeners();
    _persist(_modelKey, v);
  }

  /// 异步写盘;失败不影响本次修改,仅下次启动回到上次成功保存的值
  Future<void> _persist(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // 忽略写盘失败
    }
  }
}
