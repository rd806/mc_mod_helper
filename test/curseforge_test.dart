import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mc_mod_helper/api/curseforge.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/model/project/project_loader.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

/// JSON 响应(http.Response(String) 默认 latin1 编码,中文会抛错,必须用 bytes)
http.Response _json(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 搜索 / 分类 / 详情 / 文件 四条路由的假响应
Future<http.Response> _handler(http.Request request) async {
  final path = request.url.path;
  if (path == '/v1/minecraft/version') {
    return _json({
      'data': [
        {'versionString': '1.21.1'},
        {'versionString': '1.21.1-pre1'}, // 预发布
        {'versionString': '23w31a'}, // 快照
        {'versionString': '1.20.1'},
      ],
    });
  }
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
    final gameVersion = request.url.queryParameters['gameVersion'];
    if (gameVersion != null) {
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
        'authors': [
          {'id': 1, 'name': 'jellysquid3', 'url': 'https://example.com/a'},
        ],
      },
    });
  }
  if (path == '/v1/mods/238222/files') {
    return _json({
      'data': [
        {
          'gameVersions': ['1.21.1', 'Fabric'],
        },
        {
          'gameVersions': ['1.20.4', 'Forge', 'NeoForge'],
        },
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
    expect(m.statistics, [('downloads', '863万'), ('followers', '3200')]);
    expect(m.statisticsText, '下载 863万 · 关注 3200');
  });

  test('classId 映射到 ProjectType(表外的 classId 按模组处理)', () async {
    // CurseForge 用数字 classId 区分资源种类:4471 整合包、6552 光影
    CurseforgeApi.clientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/mods/search') {
        return _json({
          'data': [
            {'id': 1, 'name': '整合包', 'summary': '', 'classId': 4471},
            {'id': 2, 'name': '光影', 'summary': '', 'classId': 6552},
            {'id': 3, 'name': '没给 classId', 'summary': ''},
          ],
        });
      }
      if (path == '/v1/mods/4') {
        return _json({
          'data': {'id': 4, 'name': '插件', 'summary': '', 'classId': 5},
        });
      }
      if (path == '/v1/mods/4/files') return _json({'data': const []});
      return http.Response('', 404);
    });
    CurseforgeApi.clearCaches(); // 重置惰性客户端与节流时间,让上面的工厂生效

    final hits = await CurseforgeApi.search('x');
    expect(hits.map((h) => h.type), [
      ProjectType.modpack,
      ProjectType.shader,
      ProjectType.mod,
    ]);

    expect((await CurseforgeApi.getDetail('4')).type, ProjectType.plugin);
  });

  test('getDetail:name 作标题、logo 作封面、文件列表分组版本与加载器', () async {
    final d = await CurseforgeApi.getDetail('238222');
    expect(d.id, '238222');
    expect(d.title, 'Sodium');
    expect(d.source, ModSource.curseforge);
    expect(d.body, contains('高性能渲染引擎'));
    expect(d.coverUrl, 'https://media.forgecdn.net/avatars/sodium.png');
    // 版本按加载器分组(加载器名与版本号混在 gameVersions 里)
    expect(d.mcVersions, {
      projectLoaders['fabric']!: ['1.21.1'],
      projectLoaders['forge']!: ['1.20.4'],
      projectLoaders['neoforge']!: ['1.20.4'],
    });
    // 键换成 ModLoader 后,名称已是规范写法(CurseForge 本来就给这个写法)
    expect(d.mcVersions.keys.map((l) => l.name), [
      'Fabric',
      'Forge',
      'NeoForge',
    ]);
    expect(d.platform, 'Fabric / Forge / NeoForge');
    // 链接:源码命中 GitHub 品牌名,官网在列
    expect(d.links.map((l) => l.name), contains('GitHub'));
    expect(d.links.map((l) => l.name), contains('官网'));
    // 作者:API 的 authors 列表,无头像与角色
    expect(d.authors, hasLength(1));
    expect(d.authors!.single.name, 'jellysquid3');
    expect(d.authors!.single.avatarUrl, isNull);
    expect(d.authors!.single.role, isNull);
  });

  test('getCategories 翻译中文名,id 为数字字符串', () async {
    final cats = await CurseforgeApi.getCategories();
    expect(cats.map((c) => c.name), containsAll(['科技', '魔法']));
    final tech = cats.firstWhere((c) => c.name == '科技');
    expect(tech.id, '416');
    expect(tech.source, ModSource.curseforge);
  });

  test('getVersions 只保留数字编号的正式版', () async {
    final versions = await CurseforgeApi.getVersions();
    // 快照(23w31a)与预发布(1.21.1-pre1)被筛掉
    expect(versions.map((v) => v.version), ['1.21.1', '1.20.1']);
    expect(versions.first.source, ModSource.curseforge);
  });

  test('getFilteredMods:分类+版本+排序都可组合,并分页', () async {
    final uris = <Uri>[];
    CurseforgeApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      return _handler(request);
    });
    CurseforgeApi.clearCaches();

    final r1 = await CurseforgeApi.getFilteredMods(
      const Filter(
        modSource: ModSource.curseforge,
        sortMethod: SortMethod.lastEditTime,
        category: ProjectCategory(
          id: '416',
          type: ProjectType.mod,
          name: '科技',
          source: ModSource.curseforge,
        ),
        version: ProjectVersion(
          version: '1.21.1',
          source: ModSource.curseforge,
        ),
      ),
    );
    expect(r1.mods.first.id, '250898');
    expect(r1.totalPages, 3); // 45 条 / 20 每页 = 3 页
    final params = uris.single.queryParameters;
    expect(params['categoryId'], '416');
    expect(params['gameVersion'], '1.21.1');
    expect(params['sortField'], '3'); // lastEditTime → 3
    expect(params['pageSize'], '20');
    expect(params['index'], '0');

    // 翻页是 index 偏移制
    final r2 = await CurseforgeApi.getFilteredMods(
      const Filter(
        modSource: ModSource.curseforge,
        sortMethod: SortMethod.lastEditTime,
        category: ProjectCategory(
          id: '416',
          type: ProjectType.mod,
          name: '科技',
          source: ModSource.curseforge,
        ),
      ),
      page: 2,
    );
    expect(r2.mods, hasLength(1));
    expect(uris.last.queryParameters['index'], '20');
  });

  test('getFilteredMods:非法分类 id 返回空结果而非异常', () async {
    CurseforgeApi.clientFactory = () => MockClient(_handler);
    CurseforgeApi.clearCaches();

    final bad = await CurseforgeApi.getFilteredMods(
      const Filter(
        modSource: ModSource.curseforge,
        sortMethod: SortMethod.none,
        category: ProjectCategory(
          id: 'not-a-number',
          type: ProjectType.mod,
          name: '?',
          source: ModSource.curseforge,
        ),
      ),
    );
    expect(bad.mods, isEmpty);
    expect(bad.totalPages, 0);
  });

  test('getFilteredMods:默认排序映射到 sortField=1', () async {
    final uris = <Uri>[];
    CurseforgeApi.clientFactory = () => MockClient((request) async {
      uris.add(request.url);
      return _handler(request);
    });
    CurseforgeApi.clearCaches();

    await CurseforgeApi.getFilteredMods(
      const Filter(
        modSource: ModSource.curseforge,
        sortMethod: SortMethod.none,
      ),
    );
    expect(uris.single.queryParameters['sortField'], '1');
    expect(uris.single.queryParameters.containsKey('categoryId'), isFalse);
    expect(uris.single.queryParameters.containsKey('gameVersion'), isFalse);
  });
}
