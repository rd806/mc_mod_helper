import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mc_mod_helper/api/mcmod.dart';

void main() {
  setUp(() => McmodApi.clearCaches());

  test('详情页无正文面板:description 回退列表页简介,body 回退 bbcode 简介', () async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><head>'
          '<title>测试模组 - MC百科|最大的Minecraft中文MOD百科</title>'
          '</head><body></body></html>',
        ),
        200,
      ),
    );

    final d = await McmodApi.getDetail('1', fallbackDescription: '列表页简介');
    expect(d.title, '测试模组');
    // 简要介绍:cover 展示用,来自列表页/搜索页
    expect(d.description, '列表页简介');
    // 正文:bbcode 转换后的回退简介(段落标签包裹)
    expect(d.body, contains('列表页简介'));
  });

  test('fallbackDescription 为空时 description 为 null', () async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><head>'
          '<title>测试模组 - MC百科|最大的Minecraft中文MOD百科</title>'
          '</head><body></body></html>',
        ),
        200,
      ),
    );

    final d = await McmodApi.getDetail('1');
    expect(d.description, isNull);
    expect(d.body, isNull);
  });

  test('详情缓存无简介时,带列表页简介的再次访问会补上并写回缓存', () async {
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><head>'
          '<title>测试模组 - MC百科|最大的Minecraft中文MOD百科</title>'
          '</head><body></body></html>',
        ),
        200,
      ),
    );

    // 第一次:无简介入口(如旧版分类页)→ description 为 null,进入缓存
    final d1 = await McmodApi.getDetail('1');
    expect(d1.description, isNull);

    // 第二次:从搜索页带简介进入 → 缓存命中但补上简介
    final d2 = await McmodApi.getDetail('1', fallbackDescription: '列表页简介');
    expect(d2.description, '列表页简介');
    expect(d2.body, isNull); // 其余字段仍是缓存内容

    // 简介已写回缓存:第三次不带简介也能拿到
    final d3 = await McmodApi.getDetail('1');
    expect(d3.description, '列表页简介');
  });
}
