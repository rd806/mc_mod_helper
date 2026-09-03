import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/widget/captcha_dialog.dart';

/// 1x1 透明 PNG(弹窗测试需要真实可解码的图片)
const String _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// 最小挑战页 HTML(与真实站点结构一致:captchaForm + data URI 图片 + 问题)
String _captchaHtml({String question = '图中有多少个青金石 (Lapis Lazuli)?'}) {
  return '''
  <html><body><form method="POST" id="captchaForm">
    <img id="captchaImage" src="data:image/png;base64,$_tinyPng" alt="captcha">
    <p class="captcha-question">$question</p>
    <input type="number" name="cc_captcha_answer">
    <input type="hidden" name="cc_captcha_submit" value="1">
  </form></body></html>''';
}

/// 挑战页响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _captchaResponse(
  int status, {
  Map<String, String> headers = const {},
  String? question,
}) {
  return http.Response.bytes(
    utf8.encode(_captchaHtml(question: question ?? '图中有多少个青金石 (Lapis Lazuli)?')),
    status,
    headers: headers,
  );
}

void main() {
  setUp(() {
    McmodApi.clearCaches();
    SharedPreferences.setMockInitialValues({});
  });

  test('403 挑战页解析为验证码异常(问题/图片/提交地址)', () async {
    McmodApi.clientFactory = () => MockClient(
          (request) async => _captchaResponse(
            403,
            headers: {'set-cookie': 'MCMOD_SEED=seed123; path=/'},
          ),
        );

    McmodCaptchaChallenge? captured;
    try {
      await McmodApi.getDetail('1');
      fail('应抛出验证码异常');
    } on McmodCaptchaException catch (e) {
      captured = e.challenge;
    }
    expect(captured.question, contains('青金石'));
    expect(captured.imageBytes, isNotEmpty);
    // 表单无 action → 提交回被拦请求的原始地址
    expect(captured.postUrl.toString(), 'https://www.mcmod.cn/class/1.html');
  });

  test('会话 Cookie 罐:MCMOD_SEED 随验证码提交带回,通过后返回 null', () async {
    final seenCookies = <String>[];
    McmodApi.clientFactory = () => MockClient((request) async {
      if (request.method == 'GET') {
        return _captchaResponse(
          403,
          headers: {'set-cookie': 'MCMOD_SEED=seed123; path=/'},
        );
      }
      // POST:记录带回的 Cookie 与表单字段
      seenCookies.add(request.headers['cookie'] ?? '');
      expect(request.body, contains('cc_captcha_answer=42'));
      expect(request.body, contains('cc_captcha_submit=1'));
      return http.Response('<html>ok</html>', 200);
    });

    McmodCaptchaChallenge? challenge;
    try {
      await McmodApi.getDetail('1');
    } on McmodCaptchaException catch (e) {
      challenge = e.challenge;
    }
    expect(challenge, isNotNull);
    // 提交后无挑战页 → null(验证通过)
    final next = await McmodApi.submitCaptcha(challenge!, '42');
    expect(next, isNull);
    expect(seenCookies.single, contains('MCMOD_SEED=seed123'));
  });

  test('答案错误返回新挑战(换图重试的依据)', () async {
    McmodApi.clientFactory = () => MockClient((request) async {
      if (request.method == 'GET') {
        return _captchaResponse(
          403,
          headers: {'set-cookie': 'MCMOD_SEED=x; path=/'},
        );
      }
      // 答案错误:服务器返回新的挑战页(不同问题)
      return _captchaResponse(403, question: '图中有多少个钻石 (Diamond)?');
    });

    McmodCaptchaChallenge? challenge;
    try {
      await McmodApi.getDetail('1');
    } on McmodCaptchaException catch (e) {
      challenge = e.challenge;
    }
    final next = await McmodApi.submitCaptcha(challenge!, 'wrong');
    expect(next, isNotNull);
    expect(next!.question, contains('钻石'));
  });

  test('非挑战页的 403 抛出普通异常(不触发验证码流程)', () async {
    McmodApi.clientFactory = () => MockClient(
          (request) async => http.Response('<html>Forbidden</html>', 403),
        );
    await expectLater(
      McmodApi.getDetail('1'),
      throwsA(
        predicate(
          (e) => e is! McmodCaptchaException && e.toString().contains('403'),
        ),
      ),
    );
  });

  testWidgets('验证码对话框:显示问题与图片,输入答案后弹出答案', (tester) async {
    final challenge = McmodCaptchaChallenge(
      postUrl: Uri.parse('https://www.mcmod.cn/class/1.html'),
      imageBytes: base64Decode(_tinyPng),
      question: '图中有多少个青金石 (Lapis Lazuli)?',
    );

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showCaptchaDialog(context, challenge);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('安全验证'), findsOneWidget);
    expect(find.textContaining('青金石'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.text('验证并继续'));
    await tester.pumpAndSettle();
    expect(result, '42');
  });
}
