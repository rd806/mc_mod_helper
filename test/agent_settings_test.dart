import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/setting/agent_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例重置 mock 存储;load() 对缺失键赋默认值,单例随之复位
    SharedPreferences.setMockInitialValues({});
  });

  test('load 在无存档时回到默认值', () async {
    await AgentSettings.instance.load();
    expect(AgentSettings.instance.baseUrl, AgentSettings.defaultBaseUrl);
    expect(AgentSettings.instance.apiKey, '');
    expect(AgentSettings.instance.model, AgentSettings.defaultModel);
    expect(AgentSettings.instance.configured, isFalse);
  });

  test('setter 写入并可恢复', () async {
    await AgentSettings.instance.load();
    AgentSettings.instance
      ..setBaseUrl('https://api.deepseek.com/v1')
      ..setApiKey('sk-test')
      ..setModel('deepseek-chat');
    expect(AgentSettings.instance.configured, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('agent_base_url'), 'https://api.deepseek.com/v1');
    expect(prefs.getString('agent_api_key'), 'sk-test');
    expect(prefs.getString('agent_model'), 'deepseek-chat');

    // 模拟重启恢复
    SharedPreferences.setMockInitialValues({
      'agent_base_url': 'https://api.deepseek.com/v1',
      'agent_api_key': 'sk-test',
      'agent_model': 'deepseek-chat',
    });
    await AgentSettings.instance.load();
    expect(AgentSettings.instance.baseUrl, 'https://api.deepseek.com/v1');
    expect(AgentSettings.instance.apiKey, 'sk-test');
    expect(AgentSettings.instance.model, 'deepseek-chat');
  });

  test('空串/空白存储值回落默认;Key 可清空(关闭 AI 功能)', () async {
    SharedPreferences.setMockInitialValues({
      'agent_base_url': '   ',
      'agent_model': '',
    });
    await AgentSettings.instance.load();
    expect(AgentSettings.instance.baseUrl, AgentSettings.defaultBaseUrl);
    expect(AgentSettings.instance.model, AgentSettings.defaultModel);

    AgentSettings.instance
      ..setApiKey('x')
      ..setApiKey('');
    expect(AgentSettings.instance.apiKey, '');
    expect(AgentSettings.instance.configured, isFalse);

    // 地址/模型允许清空:存取空串,读取回落默认(设置页的占位提示)
    AgentSettings.instance
      ..setBaseUrl('https://api.deepseek.com/v1')
      ..setBaseUrl('')
      ..setModel('deepseek-chat')
      ..setModel('');
    expect(AgentSettings.instance.baseUrl, AgentSettings.defaultBaseUrl);
    expect(AgentSettings.instance.model, AgentSettings.defaultModel);
  });
}
