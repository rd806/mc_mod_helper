import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/model/filter.dart';
import 'package:mc_mod_helper/model/mod/mod_category.dart';
import 'package:mc_mod_helper/model/mod/mod_version.dart';
import 'package:mc_mod_helper/service/value/source.dart';

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
    // 无作者区块 → authors 为 null
    expect(d.authors, isNull);
  });

  test('详情页作者区块:头像/名称/角色解析', () async {
    // 真实结构:li.col-lg-12.author > .frame > ul > li,
    // 每项是 .avatar img + .name + .position
    McmodApi.clientFactory = () => MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          '<html><head>'
          '<title>测试模组 - MC百科|最大的Minecraft中文MOD百科</title>'
          '</head><body>'
          '<li class="col-lg-12 author"><div class="frame"><ul>'
          '<li><span class="avatar"><img '
          'src="//i.mcmod.cn/user/avatar/1.png@45x45.jpg"></span>'
          '<span class="member"><span class="name">古镇天</span>'
          '<span class="position">所有者/程序</span></span></li>'
          '<li><span class="avatar"><img '
          'src="//i.mcmod.cn/author/avatar/g.png@45x45.jpg"></span>'
          '<span class="member"><span class="name">Anvil-Dev</span>'
          '<span class="position">贡献者</span></span></li>'
          '</ul></div></li>'
          '</body></html>',
        ),
        200,
      ),
    );

    final d = await McmodApi.getDetail('1');
    expect(d.authors, hasLength(2));
    expect(d.authors!.first.name, '古镇天');
    // 协议相对地址补全为 https
    expect(
      d.authors!.first.avatarUrl,
      'https://i.mcmod.cn/user/avatar/1.png@45x45.jpg',
    );
    expect(d.authors!.first.role, '所有者/程序');
    expect(d.authors!.last.name, 'Anvil-Dev');
    expect(d.authors!.last.role, '贡献者');
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

  group('分类与版本', () {
    /// 首页假 HTML:只有分类卡片(版本信息不在首页)
    String homeHtml() => '''
<html><body>
  <div class="class_category_block" data-id="1">
    <div class="icon"><a>科技</a></div>
    <div class="text">
      <span class="i">科学技术是第一生产力。</span>
      <span class="t">科技分类</span>
    </div>
  </div>
</body></html>''';

    /// modlist 页假 HTML:两种版本的写法都要认
    /// (头部快捷入口用 href,分组列表用 onclick)+ 「远古版本」入口
    String modlistHtml() => '''
<html><body>
  <li class="main">
    <a href="//www.mcmod.cn/modlist.html?mcver=1.20.1">1.20.1 模组</a>
  </li>
  <div class="modlist-filter-block">
    <ul>
      <li title="2026更新" class="main">
        <a href="javascript:void(0);">26.x</a>
        <ul class="group">
          <li><a href="javascript:void(0);"
            onclick="window.location='/modlist.html?mcver=26.x'">26.x</a></li>
          <li><a href="javascript:void(0);"
            onclick="window.location='/modlist.html?mcver=26.1'">26.1</a></li>
        </ul>
      </li>
      <li title="足迹与故事" class="main">
        <a href="javascript:void(0);">1.20.x</a>
        <ul class="group">
          <li><a href="javascript:void(0);"
            onclick="window.location='/modlist.html?mcver=1.20.x'">1.20.x</a></li>
          <li><a href="javascript:void(0);"
            onclick="window.location='/modlist.html?mcver=1.20.1'">1.20.1</a></li>
        </ul>
      </li>
      <li class="main"><a href="javascript:void(0);"
        onclick="window.location='/modlist.html?mcver=earlier'">远古版本</a></li>
    </ul>
  </div>
</body></html>''';

    test('getCategories 解析首页的分类卡片', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(homeHtml()), 200);
      });

      final cats = await McmodApi.getCategories();
      expect(cats.single.name, '科技');
      expect(cats.single.slogan, '科学技术是第一生产力。');
      expect(uris.single.path, '/');
    });

    test('getVersions 认 href 与 onclick 两种写法,跳过「远古版本」', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(modlistHtml()), 200);
      });

      final versions = await McmodApi.getVersions();
      // 头部快捷入口(href)+ 分组列表(onclick),按文档顺序去重;
      // 1.20.1 两处都有只留一份,earlier(远古版本)不是版本号
      expect(versions.map((v) => v.version), [
        '1.20.1',
        '26.x',
        '26.1',
        '1.20.x',
      ]);
      expect(versions.first.source, ModSource.mcmod);
      // 版本列表取自 modlist 页(首页没有版本信息),且不带筛选参数
      expect(uris.single.path, '/modlist.html');
      expect(uris.single.queryParameters, isEmpty);

      // 第二次命中缓存
      await McmodApi.getVersions();
      expect(uris, hasLength(1));
    });

    test('getFilteredMods:分类+版本+排序同时生效,并分页', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(
          utf8.encode('''
<html><body>
  <div class="modlist-block">
    <div class="title">
      <p class="name"><a href="/class/459.html">[JEI] JEI物品管理器</a></p>
      <p class="ename"><a href="/class/459.html">Just Enough Items</a></p>
    </div>
    <div class="cover"><img src="//i.mcmod.cn/jei.png"></div>
    <div class="intro-content"><span>查看物品的合成与用途</span></div>
  </div>
  <div class="pagination">
    <a data-page="1" href="?page=1">1</a>
    <a data-page="2" href="?page=2">2</a>
  </div>
</body></html>'''),
          200,
        );
      });

      // 三个条件一起给出:站点的 modlist 页确实能同时应用(实测科技分类
      // 40 页 → 科技 + 1.20.1 共 15 页),所以照原样发出,不做取舍
      final r1 = await McmodApi.getFilteredMods(
        const Filter(
          modSource: ModSource.mcmod,
          featureSource: FeatureSource.lastEditTime,
          category: ModCategory(id: '1', name: '科技', source: ModSource.mcmod),
          version: ModVersion(version: '1.20.1', source: ModSource.mcmod),
        ),
      );
      expect(r1.mods.single.title, '[JEI] JEI物品管理器');
      expect(r1.totalPages, 2);
      final params = uris.single.queryParameters;
      expect(params['category'], '1');
      expect(params['mcver'], '1.20.1');
      expect(params['sort'], 'lastedittime');
      expect(params.containsKey('page'), isFalse); // 首页不带 page

      // 翻页:同一组筛选的下一页,命中各自的缓存键
      await McmodApi.getFilteredMods(
        const Filter(
          modSource: ModSource.mcmod,
          featureSource: FeatureSource.lastEditTime,
          category: ModCategory(id: '1', name: '科技', source: ModSource.mcmod),
          version: ModVersion(version: '1.20.1', source: ModSource.mcmod),
        ),
        page: 2,
      );
      expect(uris.last.queryParameters['page'], '2');
    });
  });
}
