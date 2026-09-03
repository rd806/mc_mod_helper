import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/api/source.dart';

/// JSON 响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _json(Object data) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 搜索 / 分类 / 详情 / 文件 四条路由的假响应
Future<http.Response> _handler(http.Request request) async {
  final path = request.url.path;
  if (path == '/v1/categories') {
    return _json({
      'data': [
        {'id': 416, 'name': 'Technology'},
        {'id': 417, 'name': 'Magic'},
      ],
    });
  }
  if (path == '/v1/mods/search') {
    final categoryId = request.url.queryParameters['categoryId'];
    if (categoryId != null) {
      return _json({
        'data': [
          {
            'id': 250898,
            'name': 'Create',
            'summary': 'Tech mod',
            'logo': null,
            'downloadCount': 100000,
            'followerCount': 500,
          },
        ],
        'pagination': {'totalCount': 45},
      });
    }
    return _json({
      'data': [
        {
          'id': 238222,
          'name': 'Sodium',
          'summary': 'A modern rendering engine',
          'logo': {'url': 'https://media.forgecdn.net/avatars/sodium.png'},
          'downloadCount': 8630000,
          'followerCount': 3200,
        },
      ],
      'pagination': {'totalCount': 1},
    });
  }
  if (path == '/v1/mods/238222') {
    return _json({
      'data': {
        'id': 238222,
        'name': 'Sodium',
        'summary': '高性能渲染引擎。',
        'logo': {'url': 'https://media.forgecdn.net/avatars/sodium.png'},
        'links': {
          'websiteUrl': 'https://example.com',
          'sourceUrl': 'https://github.com/CaffeineMC/sodium',
          'issuesUrl': 'https://github.com/CaffeineMC/sodium/issues',
          'wikiUrl': null,
        },
      },
    });
  }
  if (path == '/v1/mods/238222/files') {
    return _json({
      'data': [
        {'gameVersions': ['1.21.1', 'Fabric']},
        {'gameVersions': ['1.20.4', 'Forge', 'NeoForge']},
      ],
    });
  }
  return http.Response('not found', 404);
}

void main() {
  setUp(() {
    CurseforgeApi.clearCaches();
    CurseforgeApi.clientFactory = () => MockClient(_handler);
    SharedPreferences.setMockInitialValues({});
  });

  test('search 映射到 ModSummary(数字 id 字符串 + 统计)', () async {
    final results = await CurseforgeApi.search('sodium');
    expect(results, hasLength(1));
    final m = results.first;
    expect(m.id, '238222');
    expect(m.title, 'Sodium');
    expect(m.source, ModSource.curseforge);
    expect(m.statsText, '下载 863万 · 关注 3200');
  });

  test('getDetail:name 作标题、logo 作封面、文件列表分组版本与加载器', () async {
    final d = await CurseforgeApi.getDetail('238222');
    expect(d.id, '238222');
    expect(d.title, 'Sodium');
    expect(d.source, ModSource.curseforge);
    expect(d.description, contains('高性能渲染引擎'));
    expect(d.coverUrl, 'https://media.forgecdn.net/avatars/sodium.png');
    // 版本按加载器分组(加载器名与版本号混在 gameVersions 里)
    expect(d.mcVersions, {
      'fabric': ['1.21.1'],
      'forge': ['1.20.4'],
      'neoforge': ['1.20.4'],
    });
    expect(d.platform, 'Fabric / Forge / NeoForge');
    // 链接:源码命中 GitHub 品牌名,官网在列
    expect(d.links.map((l) => l.name), contains('GitHub'));
    expect(d.links.map((l) => l.name), contains('官网'));
  });

  test('getCategories 翻译中文名,id 为数字字符串', () async {
    final cats = await CurseforgeApi.getCategories();
    expect(cats.map((c) => c.name), containsAll(['科技', '魔法']));
    final tech = cats.firstWhere((c) => c.name == '科技');
    expect(tech.id, '416');
    expect(tech.source, ModSource.curseforge);
  });

  test('getCategoryMods 按分类 id 过滤并计算总页数', () async {
    final r1 = await CurseforgeApi.getCategoryMods('416');
    expect(r1.mods.first.id, '250898');
    expect(r1.totalPages, 3); // 45 条 / 20 每页 = 3 页
    final r2 = await CurseforgeApi.getCategoryMods('416', page: 2);
    expect(r2.mods, hasLength(1));
    // 非法分类 id:空结果而非异常
    final bad = await CurseforgeApi.getCategoryMods('not-a-number');
    expect(bad.mods, isEmpty);
  });
}
