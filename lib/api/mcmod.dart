import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:mc_mod_helper/value/source.dart';

import '../model/mod_category.dart';
import '../model/mod_detail.dart';
import '../model/mod_link.dart';
import '../model/mod_summary.dart';

/// 被站点限流时抛出的异常
class McmodThrottledException implements Exception {
  const McmodThrottledException();

  @override
  String toString() => '请求太频繁，请稍后再试';
}

/// 站点安全验证挑战(图形验证码,需用户手动输入)。
///
/// 表单无 action 属性,提交到被拦请求的原始地址;
/// 挑战页通过 MCMOD_SEED cookie 与提交绑定(由 McmodApi 会话 Cookie 罐维护)。
class McmodCaptchaChallenge {
  const McmodCaptchaChallenge({
    required this.postUrl,
    required this.imageBytes,
    required this.question,
  });

  /// 提交验证码的地址(被拦请求的原始地址)
  final Uri postUrl;

  /// 验证码图片 PNG 字节(挑战页内嵌 data URI)
  final Uint8List imageBytes;

  /// 验证码问题文本(如 '图中有多少个青金石 (Lapis Lazuli)?')
  final String question;
}

/// 请求被站点安全验证拦截时抛出的异常;捕获后应弹窗让用户手动输入
class McmodCaptchaException implements Exception {
  const McmodCaptchaException(this.challenge);

  final McmodCaptchaChallenge challenge;

  @override
  String toString() => '需要完成安全验证';
}

/// MC百科(mcmod.cn)数据获取服务。
///
/// 站点没有官方公开 API,这里直接抓取搜索页 / 详情页 HTML 并解析。
///
/// 站点对搜索接口有频率限制(约 3 秒内连续请求会返回“搜索太频繁”),
/// 因此本服务在客户端做了限速,并对限流响应做一次等待重试。
///
/// 站点对自动化请求部署了图形验证码(403 + 安全验证挑战页),
/// 应用侧维护会话 Cookie 罐,验证码由用户手动输入后提交。
class McmodApi {
  McmodApi._();

  /// 测试可替换的客户端工厂(测试中用 MockClient 注入假响应)
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= clientFactory();

  /// 模拟浏览器请求头,避免被站点拦截
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    'Referer': 'https://www.mcmod.cn/',
  };

  /// 会话 Cookie 罐:安全验证的 MCMOD_SEED 与验证通过后的凭证
  static final Map<String, String> _cookies = {};

  /// 请求头 + 会话 Cookie
  static Map<String, String> get _requestHeaders => {
    ..._headers,
    if (_cookies.isNotEmpty)
      'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
  };

  /// 搜索请求的最小间隔(站点限流阈值约为 3 秒)
  static const Duration _searchMinInterval = Duration(seconds: 3);

  /// www.mcmod.cn 普通页面请求的最小间隔(详情/列表/首页/分类页共用)
  static const Duration _detailMinInterval = Duration(seconds: 1);

  static DateTime? _lastSearchAt;
  static DateTime? _lastWwwAt;

  /// 会话缓存,避免重复请求触发限流
  static final Map<String, List<ModSummary>> _searchCache = {};
  static final Map<String, ModDetail> _detailCache = {};
  static List<ModCategory>? _categoryCache;
  static final Map<String, ({List<ModSummary> mods, int totalPages})>
  _categoryModsCache = {};

  /// 推荐列表的分页缓存
  /// key='$sort-$page'；
  /// 按页缓存而不是按 sort 缓存整份结果：条数上限变化时已抓页复用，只增量抓新页
  static final Map<String, List<ModSummary>> _featuredPageCache = {};

  @visibleForTesting
  static void clearCaches() {
    _searchCache.clear();
    _detailCache.clear();
    _categoryCache = null;
    _categoryModsCache.clear();
    _featuredPageCache.clear();
    _cookies.clear();
    _lastSearchAt = null;
    _lastWwwAt = null;
    // 重置惰性缓存的客户端,让测试可以替换 clientFactory
    _clientInstance = null;
  }

  /// 按关键词搜索模组,返回摘要列表
  static Future<List<ModSummary>> search(String keyword) async {
    final cached = _searchCache[keyword];
    if (cached != null) return cached;

    // filter=0 搜全部类型(站点默认)。注意:filter=1(仅模组)的排序
    // 相关性很差,本体模组会被附属模组淹没;filter=0 的排序是正确的。
    // 解析时只保留模组条目(class/数字.html),所以类型混杂不影响结果。
    final uri = Uri.parse('https://search.mcmod.cn/s')
        .replace(queryParameters: {'key': keyword, 'filter': '0', 'mold': '0'});
    final body = await _fetchWithRetry(uri, _searchMinInterval, _lastSearchAt);
    final results = _parseSearch(body);
    // 站点原始排序相关性较差(附属模组往往排在本体前面),
    // 这里按与关键词的匹配程度从高到低重新排序
    final sorted = _sortByRelevance(results, keyword);
    _searchCache[keyword] = sorted;
    return sorted;
  }

  /// 计算模组与关键词的匹配程度,分数越高越相关
  static int _relevanceScore(ModSummary m, String key) {
    final k = key.toLowerCase();
    final title = m.title.toLowerCase();
    final display = m.displayName.toLowerCase().trim();
    // 去掉末尾 (英文名) 的纯名称,如“机械动力 (Create)” -> “机械动力”
    final bare = display.replaceFirst(RegExp(r'\s*\(.*\)$'), '').trim();
    final abbr = m.abbr?.toLowerCase();
    final sub = m.subName?.toLowerCase();

    var score = 0;
    if (bare == k || title == k) score += 100; // 名称完全一致(不含英文后缀)
    if (display == k) score += 95;
    if (abbr == k) score += 90; // 缩写完全一致,如 JEI
    if (sub == k) score += 85; // 英文名完全一致
    if (bare.startsWith(k)) score += 60;
    if (display.startsWith(k)) score += 55;
    if (sub != null && sub.startsWith(k)) score += 40;
    if (display.contains(k)) score += 25;
    if (sub != null && sub.contains(k)) score += 15;
    if (m.description.toLowerCase().contains(k)) score += 5;
    return score;
  }

  /// 按相关度降序排序;分数相同时保持站点原始顺序
  static List<ModSummary> _sortByRelevance(
    List<ModSummary> results,
    String keyword,
  ) {
    final scored = results
        .asMap()
        .entries
        .map(
          (e) => (
            index: e.key,
            mod: e.value,
            score: _relevanceScore(e.value, keyword),
          ),
        )
        .toList();
    scored.sort(
      (a, b) => b.score != a.score
          ? b.score.compareTo(a.score)
          : a.index.compareTo(b.index),
    );
    return scored.map((e) => e.mod).toList();
  }

  /// 获取模组详情。[id] 为统一字符串标识(mcmod 数字字符串,如 '123')。
  ///
  /// [fallbackDescription] 用于详情页没有“概述”时回退(通常来自搜索结果)。
  static Future<ModDetail> getDetail(
    String id, {
    String? fallbackDescription,
  }) async {
    final cached = _detailCache[id];
    if (cached != null) return cached;

    final numId = int.parse(id);
    final uri = Uri.parse('https://www.mcmod.cn/class/$numId.html');
    final body = await _fetchWithRetry(uri, _detailMinInterval, _lastWwwAt);
    final detail = _parseDetail(
      id,
      body,
      fallbackDescription: fallbackDescription,
    );
    _detailCache[id] = detail;
    return detail;
  }

  /// 获取 mcmod.cn 首页“最新收录 / 最新编辑”版块的模组列表
  ///
  /// [sort]: createtime=最新收录, lastedittime=最新编辑
  /// [limit]: 返回的最大条数。为 null 时保持旧行为(仅第 1 页,约 20 条);
  ///          非空时逐页获取,直到凑满 [limit] 条或翻到末页
  ///          (列表页每页约 20 条,limit 超过 20 时需要请求多页)
  /// (首页版块内容由 JS 动态加载,这里直接取版块“更多”指向的列表页)
  static Future<List<ModSummary>> getFeaturedMods({
    String sort = 'createtime',
    int? limit,
  }) async {
    // 未指定上限:保持旧行为,只取第 1 页
    if (limit == null) {
      return _featuredPage(sort, 1);
    }
    if (limit <= 0) return const [];

    final all = <ModSummary>[];
    var page = 1;
    // 满页容量:以第 1 页条数为准,不足此数的页视为末页
    var capacity = 0;
    while (all.length < limit) {
      final mods = await _featuredPage(sort, page);
      if (page == 1) capacity = mods.length;
      all.addAll(mods);
      // 翻到末页(条目数不足一页)或出现空页:停止翻页
      if (mods.isEmpty || mods.length < capacity) break;
      page++;
    }
    // 多页累计可能略超上限(如 limit=30 需要完整两页),统一截断
    return all.take(limit).toList();
  }

  /// 获取推荐列表页第 [page] 页的模组(带会话缓存)
  static Future<List<ModSummary>> _featuredPage(String sort, int page) async {
    final key = '$sort-$page';
    final cached = _featuredPageCache[key];
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://www.mcmod.cn/modlist.html',
    ).replace(queryParameters: {'sort': sort, if (page > 1) 'page': '$page'});
    final body = await _fetchWithRetry(uri, _detailMinInterval, _lastWwwAt);
    final mods = _parseModlist(body);
    _featuredPageCache[key] = mods;
    return mods;
  }

  /// 获取 mcmod.cn 首页展示的模组分类(科技/魔法等)。
  ///
  /// 首页的分类块是服务端渲染的,直接解析 HTML 即可。
  static Future<List<ModCategory>> getCategories() async {
    final cached = _categoryCache;
    if (cached != null) return cached;

    final uri = Uri.parse('https://www.mcmod.cn/');
    final body = await _fetchWithRetry(uri, _detailMinInterval, _lastWwwAt);
    final cats = _parseCategories(body);
    _categoryCache = cats;
    return cats;
  }

  /// 获取分类列表页第 [page] 页的模组(每页约 20 个)与总页数
  static Future<({List<ModSummary> mods, int totalPages})> getCategoryMods(
    String categoryId, {
    int page = 1,
  }) async {
    final key = '$categoryId-$page';
    final cached = _categoryModsCache[key];
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://www.mcmod.cn/class/category/$categoryId-$page.html',
    );
    final body = await _fetchWithRetry(uri, _detailMinInterval, _lastWwwAt);
    final result = _parseCategoryPage(body);
    _categoryModsCache[key] = result;
    return result;
  }

  // ---------- 请求基础 ----------

  /// 抓取页面并解码为文本。
  ///
  /// 保证本次请求与上次同类型请求至少间隔 [minInterval]。
  /// [lastAt] 指向记录上次请求时间的静态字段。
  static Future<String> _get(
    Uri uri,
    Duration minInterval,
    DateTime? lastAt,
  ) async {
    if (lastAt != null) {
      final elapsed = DateTime.now().difference(lastAt);
      if (elapsed < minInterval) {
        await Future<void>.delayed(minInterval - elapsed);
      }
    }
    // 在发出请求前记录时间,保证后续请求的间隔计算正确
    _record(uri);
    final resp = await _client.get(uri, headers: _requestHeaders);
    // 保存会话 Cookie(MCMOD_SEED 在挑战页响应里下发,提交验证码要用)
    _storeCookies(resp);
    if (resp.statusCode == 403) {
      final challenge = _parseCaptchaChallenge(uri, resp);
      if (challenge != null) throw McmodCaptchaException(challenge);
      throw Exception('请求被站点安全验证拦截(HTTP 403)');
    }
    if (resp.statusCode != 200) {
      throw Exception('请求失败: HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  /// 从响应头解析 Set-Cookie 存入会话 Cookie 罐。
  ///
  /// 多个 Set-Cookie 由 http 包折叠成逗号分隔的单个值,
  /// 而 Expires 属性里也含逗号——按 'name=' 开头切分规避
  static void _storeCookies(http.Response resp) {
    final values = resp.headers['set-cookie'];
    if (values == null || values.isEmpty) return;
    for (final part in values.split(RegExp(r', (?=[A-Za-z0-9_-]+=)'))) {
      final pair = part.split(';').first.trim();
      final i = pair.indexOf('=');
      if (i > 0) {
        _cookies[pair.substring(0, i).trim()] = pair.substring(i + 1).trim();
      }
    }
  }

  /// 从 403 响应解析安全验证挑战;不是挑战页时返回 null
  static McmodCaptchaChallenge? _parseCaptchaChallenge(
    Uri requestUri,
    http.Response resp,
  ) {
    // 用 bodyBytes 按 UTF-8 解析:resp.body 在响应头缺 charset 时
    // 会按 latin1 解码,中文问题文本会变乱码
    final doc = html_parser.parse(utf8.decode(resp.bodyBytes));
    if (doc.querySelector('#captchaForm') == null) return null;
    // 挑战页内嵌 data URI 的 PNG 验证码图片
    final imgSrc = doc.querySelector('#captchaImage')?.attributes['src'] ?? '';
    const prefix = 'data:image/png;base64,';
    if (!imgSrc.startsWith(prefix)) return null;
    final bytes = base64Decode(imgSrc.substring(prefix.length));
    final question = doc.querySelector('.captcha-question')?.text.trim() ?? '';
    return McmodCaptchaChallenge(
      // 表单无 action 属性 → POST 回被拦请求的原始地址
      postUrl: requestUri,
      imageBytes: bytes,
      question: question,
    );
  }

  /// 提交安全验证答案(表单字段 cc_captcha_answer + cc_captcha_submit)。
  ///
  /// 返回 null 表示验证通过(后续请求应携带验证凭证 Cookie);
  /// 返回新的 [McmodCaptchaChallenge] 表示答案错误,需要重新输入
  static Future<McmodCaptchaChallenge?> submitCaptcha(
    McmodCaptchaChallenge challenge,
    String answer,
  ) async {
    final resp = await _client.post(
      challenge.postUrl,
      headers: {
        ..._requestHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'cc_captcha_answer': answer, 'cc_captcha_submit': '1'},
    );
    _storeCookies(resp);
    return _parseCaptchaChallenge(challenge.postUrl, resp);
  }

  /// 抓取页面;被站点限流时等待 5 秒重试一次,仍限流则抛出异常
  static Future<String> _fetchWithRetry(
    Uri uri,
    Duration minInterval,
    DateTime? lastAt,
  ) async {
    var body = await _get(uri, minInterval, lastAt);
    if (_isThrottled(body)) {
      await Future<void>.delayed(const Duration(seconds: 5));
      body = await _get(uri, Duration.zero, lastAt);
      if (_isThrottled(body)) throw const McmodThrottledException();
    }
    return body;
  }

  static void _record(Uri uri) {
    if (uri.host == 'search.mcmod.cn') {
      _lastSearchAt = DateTime.now();
    } else {
      _lastWwwAt = DateTime.now();
    }
  }

  /// 站点限流页面的特征文本
  static bool _isThrottled(String html) => html.contains('太频繁');

  // ---------- 搜索页解析 ----------

  static List<ModSummary> _parseSearch(String html) {
    final doc = html_parser.parse(html);
    final results = <ModSummary>[];
    for (final item in doc.querySelectorAll('.result-item')) {
      // .head 里第一个 a 可能是分类链接(class/category/...),
      // 需要遍历找出指向模组页(class/数字.html)的那个
      Element? anchor;
      for (final a in item.querySelectorAll('.head a')) {
        if (RegExp(r'class/\d+\.html').hasMatch(a.attributes['href'] ?? '')) {
          anchor = a;
          break;
        }
      }
      if (anchor == null) continue;
      final href = anchor.attributes['href'] ?? '';
      final idMatch = RegExp(r'class/(\d+)\.html').firstMatch(href);
      if (idMatch == null) continue;
      final title = _cleanText(anchor.text);
      if (title.isEmpty) continue;
      results.add(
        ModSummary(
          id: idMatch.group(1)!,
          title: title,
          description: _cleanText(item.querySelector('.body')?.text ?? ''),
          source: ModSource.mcmod,
        ),
      );
    }
    return results;
  }

  // ---------- 模组列表页(modlist)解析 ----------

  static List<ModSummary> _parseModlist(String html) {
    final doc = html_parser.parse(html);
    final results = <ModSummary>[];
    for (final block in doc.querySelectorAll('.modlist-block')) {
      final nameA = block.querySelector('.title .name a');
      final href = nameA?.attributes['href'] ?? '';
      final idMatch = RegExp(r'class/(\d+)\.html').firstMatch(href);
      if (idMatch == null) continue;
      final title = _cleanText(nameA?.text ?? '');
      if (title.isEmpty) continue;

      final ename = _cleanText(
        block.querySelector('.title .ename')?.text ?? '',
      );
      final intro = _cleanText(
        block.querySelector('.intro-content span')?.text ?? '',
      );
      var icon = block.querySelector('.cover img')?.attributes['src'] ?? '';
      if (icon.startsWith('//')) icon = 'https:$icon';

      results.add(
        ModSummary(
          id: idMatch.group(1)!,
          title: title,
          description: intro,
          source: ModSource.mcmod,
          subName: ename.isEmpty ? null : ename,
          iconUrl: icon.isEmpty ? null : icon,
        ),
      );
    }
    return results;
  }

  // ---------- 首页分类解析 ----------

  /// 解析首页的 9 个分类块(.class_category_block):
  /// data-id 为分类 ID,.icon a 为名称,.text span.i 为标语,
  /// .text span.t 为分类定义(站点上隐藏,但文本仍在 HTML 中)
  static List<ModCategory> _parseCategories(String html) {
    final doc = html_parser.parse(html);
    final cats = <ModCategory>[];
    for (final block in doc.querySelectorAll('.class_category_block')) {
      final id = (block.attributes['data-id'] ?? '').trim();
      if (id.isEmpty) continue;
      final name = _cleanText(block.querySelector('.icon a')?.text ?? '');
      if (name.isEmpty) continue;
      final slogan = _cleanText(
        block.querySelector('.text span.i')?.text ?? '',
      );
      final desc = _cleanText(block.querySelector('.text span.t')?.text ?? '');
      cats.add(
        ModCategory(
          id: id,
          name: name,
          slogan: slogan.isEmpty ? null : slogan,
          description: desc.isEmpty ? null : desc,
        ),
      );
    }
    return cats;
  }

  // ---------- 分类列表页解析 ----------

  /// 解析分类列表页:每个模组是 .frame > .block 卡片(封面 + 标题 + 统计),
  /// 总页数取自分页块(.pages_system)里的最大页码
  static ({List<ModSummary> mods, int totalPages}) _parseCategoryPage(
    String html,
  ) {
    final doc = html_parser.parse(html);
    final mods = <ModSummary>[];
    // 子代组合选择器锚定 .frame > .block,避免误匹配侧栏/页脚里的 .block
    for (final block in doc.querySelectorAll('div.frame > div.block')) {
      final nameA = block.querySelector('.name.t a');
      final href = nameA?.attributes['href'] ?? '';
      final idMatch = RegExp(r'class/(\d+)\.html').firstMatch(href);
      if (idMatch == null) continue;
      final title = _cleanText(nameA?.text ?? '');
      if (title.isEmpty) continue;

      var icon = block.querySelector('img.img')?.attributes['src'] ?? '';
      if (icon.startsWith('//')) icon = 'https:$icon';
      // none.jpg 是站点无封面时的占位图,不展示
      if (icon.contains('/none.jpg')) icon = '';

      // 统计:浏览/推荐/收藏,逐项判空拼接
      final views = _cleanText(block.querySelector('.num')?.text ?? '');
      final push = _cleanText(block.querySelector('.push')?.text ?? '');
      final like = _cleanText(block.querySelector('.like')?.text ?? '');
      final stats = <String>[
        if (views.isNotEmpty) '浏览 $views',
        if (push.isNotEmpty) '推荐 $push',
        if (like.isNotEmpty) '收藏 $like',
      ];
      mods.add(
        ModSummary(
          id: idMatch.group(1)!,
          title: title,
          description: '',
          source: ModSource.mcmod,
          iconUrl: icon.isEmpty ? null : icon,
          statsText: stats.isEmpty ? null : stats.join(' · '),
        ),
      );
    }
    // 没有分页块(单页分类)时兜底为 1 页
    var totalPages = 1;
    final page = doc.querySelector('.pages_system');
    if (page != null) {
      for (final a in page.querySelectorAll('a[href]')) {
        final m = RegExp(r'category/\d+-(\d+)\.html')
            .firstMatch(a.attributes['href'] ?? '');
        if (m != null) {
          final n = int.tryParse(m.group(1)!);
          if (n != null && n > totalPages) totalPages = n;
        }
      }
    }
    return (mods: mods, totalPages: totalPages);
  }

  // ---------- 详情页解析 ----------

  static ModDetail _parseDetail(
    String id,
    String html, {
    String? fallbackDescription,
  }) {
    final doc = html_parser.parse(html);

    // 标题:<title>中文名 (English) - MC百科|...</title>
    var title =
        doc
            .querySelector('title')
            ?.text
            .replaceFirst(RegExp(r'\s*-\s*MC百科.*$'), '') ??
        '';
    String? subName;
    final paren = RegExp(r'\((.*?)\)$').firstMatch(title);
    if (paren != null && RegExp(r'[A-Za-z]').hasMatch(paren.group(1)!)) {
      subName = paren.group(1);
      title = title.substring(0, paren.start).trim();
    }

    // 封面图
    String? coverUrl;
    final cover = doc.querySelector('img[src*="i.mcmod.cn/class/cover"]');
    if (cover != null) {
      var src = cover.attributes['src'] ?? '';
      if (src.startsWith('//')) src = 'https:$src';
      coverUrl = src;
    }

    // 相关链接(CurseForge / GitHub / ...)
    final links = <ModLink>[];
    for (final li in doc.querySelectorAll('ul.common-link-icon-frame li')) {
      final a = li.querySelector('a[href]');
      final name =
          (li.querySelector('.name')?.text ??
                  a?.attributes['data-original-title'] ??
                  '')
              .trim();
      var href = a?.attributes['href'] ?? '';
      // 外链经 link.mcmod.cn/target/<base64> 中转,解码出真实地址
      final target = href.indexOf('/target/');
      if (href.contains('link.mcmod.cn') && target >= 0) {
        final encoded = href.substring(target + 8);
        try {
          href = utf8.decode(base64.decode(base64.normalize(encoded)));
        } catch (_) {
          // 解码失败时保留原始跳转地址
        }
      }
      if (name.isNotEmpty && href.isNotEmpty) {
        links.add(ModLink(name: name, url: href));
      }
    }

    // 支持的 MC 版本:按加载器分组(去重,保持页面顺序)。
    // 页面结构:li.mcver > ul > ul,每个内层 ul 的首个 li 是加载器标签
    // (如 'Forge: '),其余 li 的链接为版本号
    final mcVersions = <String, List<String>>{};
    for (final group in doc.querySelectorAll('li.mcver > ul > ul')) {
      final label = group.querySelector('li')?.text.trim() ?? '';
      final loader = label.replaceFirst(RegExp(r'[:：]\s*$'), '');
      final versions = <String>[];
      for (final a in group.querySelectorAll('li a')) {
        final v = a.text.trim();
        if (v.isNotEmpty && !versions.contains(v)) versions.add(v);
      }
      if (loader.isNotEmpty) mcVersions[loader] = versions;
    }

    String? field(String label) {
      final m = RegExp('$label[:：]\\s*([^<]+)<').firstMatch(html);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    // 左侧信息面板:支持平台 / 运行环境(直接对 HTML 文本做正则)
    String convertToEnum(String chinese) {
      switch (chinese) {
        case '需装':
        case '客户端需装':
        case '服务端需装':
          return 'required';
        case '可选':
        case '客户端可选':
        case '服务端可选':
          return 'optional';
        case '无效':
        case '客户端无效':
        case '服务端无效':
          return 'unsupported';
        default:
          return chinese; // 或者抛出异常
      }
    }

    List<String>? getEnvironment(String? value) {
      if (value == null || value.isEmpty) return null;
      // 站点格式形如 '客户端需装，服务端无效',中英文逗号都可能出现,
      // 且可能只有一侧;拆开后逐个转成 required/optional/unsupported
      final parts = value
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return parts.map(convertToEnum).toList();
    }

    // 统计信息(最多 3 项):总浏览、昨日指数,再补面板其余条目。
    // 页面结构:.infos > .span 每块是 数值(.n) + 标签(.t);
    // 昨日指数单独在头部文本里(如 '昨日指数: 9080')
    List<(String, String)>? parseStatistics() {
      final panel = <(String, String)>[];
      for (final span in doc.querySelectorAll('.infos .span')) {
        final n = span.querySelector('.n')?.text.trim() ?? '';
        final t = span.querySelector('.t')?.text.trim() ?? '';
        if (n.isEmpty || t.isEmpty) continue;
        panel.add((_statKey(t), n));
        if (panel.length >= 3) break;
      }
      if (panel.isEmpty) return null;
      // 排序:面板第一条(通常总浏览)最前,其次昨日指数,再补其余条目
      final stats = <(String, String)>[panel.first];
      final index = RegExp(r'昨日指数[:：]\s*([0-9]+)')
          .firstMatch(doc.body?.text ?? '');
      if (index != null && stats.length < 3) {
        stats.add(('index', index.group(1)!));
      }
      for (final s in panel.skip(1)) {
        if (stats.length >= 3) break;
        stats.add(s);
      }
      return stats;
    }

    // 简介:取详情页正文面板(.text-area.common-text)的全部富文本 HTML,
    // 即完整的“模组介绍”内容;页面没有该面板时回退到搜索页 wiki 简介
    final description =
        _extractFullContentHtml(doc) ??
        _bbcodeToHtml(fallbackDescription ?? '');

    return ModDetail(
      id: id,
      title: title,
      source: ModSource.mcmod,
      subName: subName,
      body: description.isEmpty ? null : description,
      coverUrl: coverUrl,
      links: links,
      mcVersions: mcVersions,
      platform: field('支持平台'),
      environment: getEnvironment(field('运行环境')),
      statistics: parseStatistics(),
    );
  }

  /// 统计面板标签 → 统计 key(cover 按 key 选图标;未知标签原样保留,
  /// 由兜底卡片按原文展示)
  static String _statKey(String label) {
    switch (label) {
      case '总浏览':
        return 'views';
      case '资料填充率':
        return 'fillRate';
      default:
        return label;
    }
  }

  /// 提取详情页正文面板的全部富文本 HTML。
  ///
  /// 正文面板(`li.text-area.common-text`)就是完整的“模组介绍”内容:
  /// 所有小节(概述/控制/截图/模组介绍等)都渲染在这个面板里。
  /// 页面没有该面板时返回 null。
  static String? _extractFullContentHtml(Document doc) {
    final panel = doc.querySelector('.text-area.common-text');
    if (panel == null) return null;
    final inner = panel.innerHtml.trim();
    if (inner.isEmpty) return null;
    return _sanitizeHtml(_styleSectionTitles(inner));
  }

  /// 把小节标题 span(common-text-title-1/2/3)转成带字号的加粗标题
  static String _styleSectionTitles(String html) {
    const sizes = {'1': '1.35', '2': '1.2', '3': '1.1'};
    return html.replaceAllMapped(
      RegExp(r'<span[^>]*class="[^"]*common-text-title-(\d)[^"]*"[^>]*>'),
      (m) {
        final size = sizes[m.group(1)] ?? '1';
        return '<span style="font-weight:bold;font-size:${size}em">';
      },
    );
  }

  /// 清洗详情页富文本 HTML,使其适合在 app 内渲染
  static String _sanitizeHtml(String html) {
    var s = html;
    // 正文面板里混有站内弹窗的内联脚本,直接剥掉
    s = s.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    // 懒加载图片:真实地址在 data-src,替换掉占位 loading 图
    s = s.replaceAllMapped(
      RegExp(r'\s+src="[^"]*loading[^"]*"(\s+data-src="([^"]*)")'),
      (m) => ' src="${m.group(2)!}"',
    );
    s = s.replaceAll(RegExp(r'\s+data-src="[^"]*"'), '');
    s = s.replaceAll(RegExp(r'\s+data-error="[^"]*"'), '');
    // 图片:去掉固定宽高与 class(排版由 HtmlContent 渲染器负责:
    // 表格内画廊固定高度、正文图片限制宽度),包一层链接,
    // 点击图片时在灯箱中放大查看
    s = s.replaceAllMapped(RegExp(r'<img([^>]*)>'), (m) {
      final attrs = m.group(1)!;
      final src = RegExp(r'src="([^"]*)"').firstMatch(attrs)?.group(1);
      final cleaned = attrs
          .replaceAll(RegExp(r'\s+(width|height)="[^"]*"'), '')
          .replaceAll(RegExp(r'\s+(class|style)="[^"]*"'), '');
      return (src == null || src.isEmpty)
          ? '<img$cleaned>'
          : '<a href="$src"><img$cleaned></a>';
    });
    // 文字表格:剥掉站点自带的百分比宽度。
    // hyper_render 对带百分比宽度的表格走 fitWidth 策略(列压窄、
    // 文字换行,表格变得很高);去掉后按内容自然宽度布局,超宽时由
    // 渲染器的横向滚动容器兜底。画廊表格(含图片)保留百分比宽度——
    // 图片按容器缩放比横向滚动更合适
    s = s.replaceAllMapped(RegExp(r'<table[^>]*>.*?</table>', dotAll: true), (
      m,
    ) {
      final block = m.group(0)!;
      if (block.contains('<img')) return block;
      return block.replaceFirstMapped(RegExp(r'<table[^>]*>'), (tm) {
        var tag = tm.group(0)!;
        tag = tag.replaceAll(RegExp(r'\s+width="[^"]*%"'), '');
        tag = tag.replaceAllMapped(RegExp(r'style="([^"]*)"'), (sm) {
          final cleaned = sm
              .group(1)!
              .split(';')
              .where(
                (decl) =>
                    !(decl.toLowerCase().contains('width') &&
                        decl.contains('%')),
              )
              .join(';');
          return cleaned.trim().isEmpty ? '' : 'style="$cleaned"';
        });
        return tag;
      });
    });

    // 站内弹窗链接(javascript:void(0))只保留文字
    s = s.replaceAllMapped(
      RegExp(r'<a[^>]*href="javascript:[^"]*"[^>]*>(.*?)</a>', dotAll: true),
      (m) => '<span>${m.group(1)}</span>',
    );
    // 协议相对地址补全
    s = s.replaceAll('src="//', 'src="https://');
    s = s.replaceAll('href="//', 'href="https://');
    return s;
  }

  /// 把搜索页返回的 wiki/BBCode 简介转成 HTML(简介区的回退方案)
  static String _bbcodeToHtml(String text) {
    // 先转义正文,再处理 wiki 标记
    var s = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    // 配对标签
    final pairs = <String, (String, String)>{
      'b': ('<strong>', '</strong>'),
      'i': ('<em>', '</em>'),
      'u': ('<u>', '</u>'),
      's': ('<del>', '</del>'),
      'center': ('<p style="text-align:center">', '</p>'),
      'quote': ('<blockquote>', '</blockquote>'),
      'code': ('<pre>', '</pre>'),
      'spoiler': ('<details><summary>剧透内容</summary>', '</details>'),
    };
    for (final entry in pairs.entries) {
      final tag = entry.key;
      s = s.replaceAllMapped(
        RegExp(
          '\\[$tag\\](.*?)\\[/$tag\\]',
          dotAll: true,
          caseSensitive: false,
        ),
        (m) => '${entry.value.$1}${m.group(1)}${entry.value.$2}',
      );
    }
    // [color=xxx]..[/color]
    s = s.replaceAllMapped(
      RegExp(
        r'\[color=([^\]]*)\](.*?)\[/color\]',
        dotAll: true,
        caseSensitive: false,
      ),
      (m) => '<span style="color:${m.group(1)}">${m.group(2)}</span>',
    );
    // [url=xxx]label[/url] 与 [url]xxx[/url]
    s = s.replaceAllMapped(
      RegExp(
        r'\[url=([^\]]*)\](.*?)\[/url\]',
        dotAll: true,
        caseSensitive: false,
      ),
      (m) => '<a href="${m.group(1)}">${m.group(2)}</a>',
    );
    s = s.replaceAllMapped(
      RegExp(r'\[url\](.*?)\[/url\]', dotAll: true, caseSensitive: false),
      (m) => '<a href="${m.group(1)}">${m.group(1)}</a>',
    );
    // [img]url[/img]
    s = s.replaceAllMapped(
      RegExp(r'\[img\](.*?)\[/img\]', dotAll: true, caseSensitive: false),
      (m) => '<img src="${m.group(1)}" style="max-width:100%">',
    );

    // 标题:[h1=xxx] ~ [h4=xxx]
    const headingStyles = {
      'h1': 'font-weight:bold;font-size:1.35em;margin:12px 0 8px',
      'h2': 'font-weight:bold;font-size:1.2em;margin:10px 0 6px',
      'h3': 'font-weight:bold;font-size:1.1em;margin:8px 0 4px',
      'h4': 'font-weight:bold;margin:6px 0 2px',
    };
    for (final entry in headingStyles.entries) {
      s = s.replaceAllMapped(
        RegExp('\\[${entry.key}=([^\\]]*)\\]', caseSensitive: false),
        (m) => '<p style="${entry.value}">${m.group(1)}</p>',
      );
    }

    // 列表:[list] 内以 [*] 分隔的条目
    s = s.replaceAllMapped(
      RegExp(r'\[list=1\](.*?)\[/list\]', dotAll: true, caseSensitive: false),
      (m) => _renderList(m.group(1)!, ordered: true),
    );
    s = s.replaceAllMapped(
      RegExp(r'\[list\](.*?)\[/list\]', dotAll: true, caseSensitive: false),
      (m) => _renderList(m.group(1)!, ordered: false),
    );

    // 单行标记:[mark:xxx]、[icon:xxx] 直接丢弃,[line] 换成分隔线
    s = s.replaceAll(RegExp(r'\[(?:mark|icon|media|bilibili)[^\]]*\]'), '');
    s = s.replaceAll(RegExp(r'\[line\]', caseSensitive: false), '<hr>');

    // 残留的未知 wiki 标记一律丢弃(仅小写,避免误删 [ABBR] 之类正文)
    s = s.replaceAll(RegExp(r'\[/?[a-z]+(?:=[^\]]*)?\]'), '');

    // 换行
    s = s.replaceAll(RegExp(r'\n+'), '<br>');
    return s.trim();
  }

  static String _renderList(String content, {required bool ordered}) {
    final tag = ordered ? 'ol' : 'ul';
    final items = content
        .split('[*]')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    return '<$tag>${items.map((e) => '<li>$e</li>').join()}</$tag>';
  }

  /// wiki 标记,如 [h1=概述]、[icon:toughness=100]、[mark:title_menu]
  static final RegExp _wikiTagRe = RegExp(r'\[[a-z][a-z0-9_:.-]*[^\]]*\]');

  /// 去掉 wiki 标记,保留换行
  static String _stripWikiTags(String text) => text.replaceAll(_wikiTagRe, '');

  /// 压缩空白并去掉 wiki 标记
  static String _cleanText(String text) {
    return _stripWikiTags(text).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
