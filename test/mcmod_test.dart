import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mc_mod_helper/api/mcmod.dart';
import 'package:mc_mod_helper/model/filter/filter.dart';
import 'package:mc_mod_helper/model/filter/sort_method.dart';
import 'package:mc_mod_helper/model/project/project_category.dart';
import 'package:mc_mod_helper/model/project/project_loader.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/model/project/project_version.dart';
import 'package:mc_mod_helper/setting/value/source.dart';

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

      final cats = await McmodApi.getCategories(ProjectType.mod);
      expect(cats.single.name, '科技');
      expect(cats.single.slogan, '科学技术是第一生产力。');
      // 本站没有类型字段:本应用用到的接口(modlist / class 页)全是模组
      expect(cats.single.type, ProjectType.mod);
      expect(uris.single.path, '/');
    });

    test('getVersions 认 href 与 onclick 两种写法,跳过「远古版本」', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(modlistHtml()), 200);
      });

      final versions = await McmodApi.getVersions(ProjectType.mod);
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
      await McmodApi.getVersions(ProjectType.mod);
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
          type: ProjectType.mod,
          modSource: ModSource.mcmod,
          sortMethod: SortMethod.lastEditTime,
          category: ProjectCategory(
            id: '1',
            type: ProjectType.mod,
            name: '科技',
            source: ModSource.mcmod,
          ),
          version: ProjectVersion(version: '1.20.1', source: ModSource.mcmod),
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
          type: ProjectType.mod,
          modSource: ModSource.mcmod,
          sortMethod: SortMethod.lastEditTime,
          category: ProjectCategory(
            id: '1',
            type: ProjectType.mod,
            name: '科技',
            source: ModSource.mcmod,
          ),
          version: ProjectVersion(version: '1.20.1', source: ModSource.mcmod),
        ),
        page: 2,
      );
      expect(uris.last.queryParameters['page'], '2');
    });
  });

  group('整合包', () {
    /// 首页假 HTML(模组分类的来源,用来验证两类分类互不干扰)
    String homeHtml() => '''
<html><body>
  <div class="class_category_block" data-id="1">
    <div class="icon"><a>科技</a></div>
    <div class="text"><span class="i">标语</span><span class="t">描述</span></div>
  </div>
</body></html>''';

    /// modpack.html 假 HTML(按真实页面结构):条目 href 是 /modpack/N.html,
    /// 分类筛选块是纯文本链接(说明在 title 上),版本块与模组页同构
    String modpackHtml() => '''
<html><body>
  <div class="modlist-filter-block category">
    <div class="title">整合包元素:</div>
    <ul>
      <li class="main"><span>全部</span></li>
      <li class="main">
        <a class="normal gray" href="javascript:void(0);"
          onclick="window.location='/modpack.html?category=1'"
          title="含有科技类模组。">科技</a>
      </li>
      <li class="main">
        <a class="normal gray" href="javascript:void(0);"
          onclick="window.location='/modpack.html?category=9'"
          title="占据主要玩法的核心模组数量较多。">大型</a>
      </li>
    </ul>
  </div>
  <div class="modlist-filter-block mcver">
    <ul>
      <li><a href="javascript:void(0);"
        onclick="window.location='/modpack.html?mcver=1.12.2'">1.12.2</a></li>
      <li><a href="javascript:void(0);"
        onclick="window.location='/modpack.html?mcver=earlier'">远古版本</a></li>
    </ul>
  </div>
  <div class="modlist-block">
    <div class="intro"><a class="intro-content">
      <span>低配机的冒险福音,强优化!</span></a></div>
    <div class="cover"><img src="//i.mcmod.cn/modpack/cover/883.jpg@170x115.jpg"></div>
    <div class="title">
      <p class="name"><a href="/modpack/883.html">[TC] 剑拔弩张之时</a></p>
      <p class="ename"><a href="/modpack/883.html">&nbsp;</a></p>
    </div>
  </div>
  <div class="modlist-block">
    <div class="intro"><a class="intro-content">
      <span>1.12.2 拔刀剑整合包</span></a></div>
    <div class="cover"><img src="//i.mcmod.cn/modpack/cover/1314.jpg@170x115.jpg"></div>
    <div class="title">
      <p class="name"><a href="/modpack/1314.html">拔刀之旅</a></p>
      <p class="ename"><a href="/modpack/1314.html">Battou No Tabi</a></p>
    </div>
  </div>
  <div class="pagination"><a data-page="1" href="?page=1">1</a>
    <a data-page="47" href="?page=47">47</a></div>
</body></html>''';

    test('列表:走 modpack.html,id 取自 /modpack/N.html,条目类型是整合包', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(modpackHtml()), 200);
      });

      final r = await McmodApi.getFilteredMods(
        const Filter(
          type: ProjectType.modpack,
          modSource: ModSource.mcmod,
          sortMethod: SortMethod.none,
        ),
      );
      expect(uris.single.path, '/modpack.html');
      expect(r.totalPages, 47); // 分页链接的 data-page 最大值
      expect(r.mods, hasLength(2));
      final first = r.mods.first;
      expect(first.id, '883');
      expect(first.type, ProjectType.modpack);
      expect(first.title, '[TC] 剑拔弩张之时');
      expect(first.subName, isNull); // ename 是 &nbsp; → 空
      expect(first.description, '低配机的冒险福音,强优化!');
      // 封面走 modpack 目录,协议相对地址补全
      expect(
        first.iconUrl,
        'https://i.mcmod.cn/modpack/cover/883.jpg@170x115.jpg',
      );
      expect(r.mods.last.subName, 'Battou No Tabi');
      // 详情页地址也按类型拼(收藏页 / 浏览器打开用)
      expect(first.pageUrl, 'https://www.mcmod.cn/modpack/883.html');
    });

    test('列表:分类/版本/排序参数与模组页通用', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(modpackHtml()), 200);
      });

      await McmodApi.getFilteredMods(
        const Filter(
          type: ProjectType.modpack,
          modSource: ModSource.mcmod,
          sortMethod: SortMethod.createTime,
          category: ProjectCategory(
            id: '9',
            type: ProjectType.modpack,
            name: '大型',
            source: ModSource.mcmod,
          ),
          version: ProjectVersion(version: '1.12.2', source: ModSource.mcmod),
        ),
      );
      final params = uris.single.queryParameters;
      expect(uris.single.path, '/modpack.html');
      expect(params['category'], '9');
      expect(params['mcver'], '1.12.2');
      expect(params['sort'], 'createtime');
    });

    test('分类:取 modpack.html 里的筛选块(名称/说明/id 按类型分开缓存)', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        if (request.url.path == '/') {
          // 首页(模组分类的来源),不应被整合包这条路径用到
          return http.Response.bytes(utf8.encode(homeHtml()), 200);
        }
        return http.Response.bytes(utf8.encode(modpackHtml()), 200);
      });

      final cats = await McmodApi.getCategories(ProjectType.modpack);
      expect(uris.single.path, '/modpack.html');
      expect(cats.map((c) => c.name), ['科技', '大型']);
      expect(cats.first.id, '1');
      expect(cats.first.type, ProjectType.modpack);
      expect(cats.first.description, '含有科技类模组。');
      expect(cats.last.id, '9');

      // 同类型第二次命中缓存
      await McmodApi.getCategories(ProjectType.modpack);
      expect(uris, hasLength(1));

      // 换回模组类型:走首页那份,与整合包互不干扰(id 体系不同)
      final modCats = await McmodApi.getCategories(ProjectType.mod);
      expect(uris.last.path, '/');
      expect(modCats.single.type, ProjectType.mod);
    });

    test('版本选项:取 modpack.html,跳过「远古版本」', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(utf8.encode(modpackHtml()), 200);
      });

      final versions = await McmodApi.getVersions(ProjectType.modpack);
      expect(uris.single.path, '/modpack.html');
      expect(versions.map((v) => v.version), ['1.12.2']);
    });

    test('详情:走 /modpack/N.html,封面取 modpack 目录,无平台/环境字段', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        return http.Response.bytes(
          utf8.encode('''
<html><head>
  <title>[TC] 剑拔弩张之时 - MC百科|最大的Minecraft中文MOD百科</title>
</head><body>
  <img src="//i.mcmod.cn/modpack/cover/883.jpg@170x115.jpg" />
  <li class="col-lg-4">整合包类型: <a href="/modpack.html?mold=2">魔改整合</a></li>
  <li class="col-lg-4">运作方式: <a href="/modpack.html?api=1">Forge</a></li>
  <li class="col-lg-12 mcver">
    <ul><ul>
      <li>Forge: </li>
      <li><a href="/modpack.html?api=1&amp;mcver=1.12.2">1.12.2</a></li>
    </ul></ul>
  </li>
  <li class="col-lg-12 author"><div class="frame"><ul>
    <li><span class="avatar"><img src="//i.mcmod.cn/user/1.png@45x45.jpg"></span>
      <span class="member"><span class="name">水咬狸花猫</span>
      <span class="position">所有者/美术</span></span></li>
  </ul></div></li>
  <div class="common-link-frame">
    <ul class="common-link-icon-frame common-link-icon-frame-style-3">
      <li><a href="//link.mcmod.cn/target/aHR0cHM6Ly9wYW4ucXVhcmsuY24vcy9j">
        <span title="夸克网盘" class="name">夸克网盘</span></a></li>
    </ul>
  </div>
  <li class="text-area common-text"><p>这是整合包正文。</p></li>
</body></html>'''),
          200,
        );
      });

      final d = await McmodApi.getDetail(
        '883',
        type: ProjectType.modpack,
        fallbackDescription: '列表页简介',
      );
      expect(uris.single.path, '/modpack/883.html');
      expect(d.type, ProjectType.modpack);
      expect(d.title, '[TC] 剑拔弩张之时');
      expect(d.description, '列表页简介');
      expect(
        d.coverUrl,
        'https://i.mcmod.cn/modpack/cover/883.jpg@170x115.jpg',
      );
      expect(d.body, contains('这是整合包正文'));
      // 信息面板:整合包页没有「支持平台 / 运行环境」两个字段,
      // 它的加载器信息在版本分组里(见下面那条断言)
      expect(d.platform, isNull);
      expect(d.sides, isNull);
      // 与模组页同构的部分照常解析:版本按加载器分组、作者、相关链接
      expect(d.mcVersions[ProjectLoader.of('Forge')], ['1.12.2']);
      expect(d.authors!.single.name, '水咬狸花猫');
      expect(d.links.single.name, '夸克网盘');
      expect(d.pageUrl, 'https://www.mcmod.cn/modpack/883.html');
    });

    test('详情缓存按「类型+id」分开:同号模组与整合包互不覆盖', () async {
      final uris = <Uri>[];
      McmodApi.clientFactory = () => MockClient((request) async {
        uris.add(request.url);
        final isPack = request.url.path.startsWith('/modpack/');
        return http.Response.bytes(
          utf8.encode(
            '<html><head><title>${isPack ? '整合包' : '模组'}${request.url.path} - MC百科</title></head><body></body></html>',
          ),
          200,
        );
      });

      final pack = await McmodApi.getDetail('883', type: ProjectType.modpack);
      final mod = await McmodApi.getDetail('883');
      expect(pack.type, ProjectType.modpack);
      expect(mod.type, ProjectType.mod);
      expect(uris.map((u) => u.path), ['/modpack/883.html', '/class/883.html']);
    });
  });
}
