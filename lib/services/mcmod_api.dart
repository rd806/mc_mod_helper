import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/mod.dart';

/// 被站点限流时抛出的异常
class McmodThrottledException implements Exception {
    const McmodThrottledException();

    @override
    String toString() => '请求太频繁,被站点限流,请稍后再试';
}

/// MC百科(mcmod.cn)数据获取服务。
///
/// 站点没有官方公开 API,这里直接抓取搜索页 / 详情页 HTML 并解析。
///
/// 站点对搜索接口有频率限制(约 3 秒内连续请求会返回“搜索太频繁”),
/// 因此本服务在客户端做了限速,并对限流响应做一次等待重试。
class McmodApi {
    McmodApi._();

    static final http.Client _client = http.Client();

    /// 模拟浏览器请求头,避免被站点拦截
    static const Map<String, String> _headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'Referer': 'https://www.mcmod.cn/',
    };

    /// 搜索请求的最小间隔(站点限流阈值约为 3 秒)
    static const Duration _searchMinInterval = Duration(seconds: 3);

    /// 详情请求的最小间隔
    static const Duration _detailMinInterval = Duration(seconds: 1);

    static DateTime? _lastSearchAt;
    static DateTime? _lastDetailAt;

    /// 会话缓存,避免重复请求触发限流
    static final Map<String, List<ModSummary>> _searchCache = {};
    static final Map<int, ModDetail> _detailCache = {};
    static final Map<String, List<ModSummary>> _featuredCache = {};

    /// 按关键词搜索模组,返回摘要列表
    static Future<List<ModSummary>> search(String keyword) async {
        final cached = _searchCache[keyword];
        if (cached != null) return cached;

        // filter=0 搜全部类型(站点默认)。注意:filter=1(仅模组)的排序
        // 相关性很差,本体模组会被附属模组淹没;filter=0 的排序是正确的。
        // 解析时只保留模组条目(class/数字.html),所以类型混杂不影响结果。
        final uri = Uri.parse('https://search.mcmod.cn/s').replace(
        queryParameters: {'key': keyword, 'filter': '0', 'mold': '0'},
        );
        var body = await _get(uri, _searchMinInterval, _lastSearchAt);
        if (_isThrottled(body)) {
        // 被站点限流,等待后重试一次
        await Future<void>.delayed(const Duration(seconds: 5));
        body = await _get(uri, Duration.zero, _lastSearchAt);
        if (_isThrottled(body)) throw const McmodThrottledException();
        }
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
            .map((e) => (
                index: e.key,
                mod: e.value,
                score: _relevanceScore(e.value, keyword),
                ))
            .toList();
        scored.sort((a, b) =>
            b.score != a.score ? b.score.compareTo(a.score) : a.index.compareTo(b.index));
        return scored.map((e) => e.mod).toList();
    }

    /// 获取模组详情。
    ///
    /// [fallbackDescription] 用于详情页没有“概述”时回退(通常来自搜索结果)。
    static Future<ModDetail> getDetail(
        int id, {
        String? fallbackDescription,
    }) async {
        final cached = _detailCache[id];
        if (cached != null) return cached;

        final uri = Uri.parse('https://www.mcmod.cn/class/$id.html');
        var body = await _get(uri, _detailMinInterval, _lastDetailAt);
        if (_isThrottled(body)) {
        await Future<void>.delayed(const Duration(seconds: 5));
        body = await _get(uri, Duration.zero, _lastDetailAt);
        if (_isThrottled(body)) throw const McmodThrottledException();
        }
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
    /// [sort]:createtime=最新收录,lastedittime=最新编辑
    /// (首页版块内容由 JS 动态加载,这里直接取版块“更多”指向的列表页)
    static Future<List<ModSummary>> getFeaturedMods({
        String sort = 'createtime',
    }) async {
        final cached = _featuredCache[sort];
        if (cached != null) return cached;

        final uri = Uri.parse('https://www.mcmod.cn/modlist.html')
            .replace(queryParameters: {'sort': sort});
        var body = await _get(uri, _detailMinInterval, _lastDetailAt);
        if (_isThrottled(body)) {
        await Future<void>.delayed(const Duration(seconds: 5));
        body = await _get(uri, Duration.zero, _lastDetailAt);
        if (_isThrottled(body)) throw const McmodThrottledException();
        }
        final results = _parseModlist(body);
        _featuredCache[sort] = results;
        return results;
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
        final resp = await _client.get(uri, headers: _headers);
        if (resp.statusCode != 200) {
        throw Exception('请求失败: HTTP ${resp.statusCode}');
        }
        return utf8.decode(resp.bodyBytes);
    }

    static void _record(Uri uri) {
        if (uri.host == 'search.mcmod.cn') {
            _lastSearchAt = DateTime.now();
        } else {
            _lastDetailAt = DateTime.now();
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
        results.add(ModSummary(
            id: int.parse(idMatch.group(1)!),
            title: title,
            description: _cleanText(item.querySelector('.body')?.text ?? ''),
        ));
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

        final ename = _cleanText(block.querySelector('.title .ename')?.text ?? '');
        final intro = _cleanText(
            block.querySelector('.intro-content span')?.text ?? '',
        );
        var icon = block.querySelector('.cover img')?.attributes['src'] ?? '';
        if (icon.startsWith('//')) icon = 'https:$icon';

        results.add(ModSummary(
            id: int.parse(idMatch.group(1)!),
            title: title,
            description: intro,
            subName: ename.isEmpty ? null : ename,
            iconUrl: icon.isEmpty ? null : icon,
        ));
        }
        return results;
    }

    // ---------- 详情页解析 ----------

    static ModDetail _parseDetail(
        int id,
        String html, {
        String? fallbackDescription,
    }) {
        final doc = html_parser.parse(html);

        // 标题:<title>中文名 (English) - MC百科|...</title>
        var title = doc
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
        final name = (li.querySelector('.name')?.text ??
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

        // 支持的 MC 版本(去重,保持顺序)
        final mcVersions = <String>[];
        for (final a in doc.querySelectorAll('li.mcver a')) {
        final v = a.text.trim();
        if (v.isNotEmpty && !mcVersions.contains(v)) mcVersions.add(v);
        }

        // 左侧信息面板:支持平台 / 运行环境(直接对 HTML 文本做正则)
        String? field(String label) {
        final m = RegExp('$label[:：]\\s*([^<]+)<').firstMatch(html);
        final v = m?.group(1)?.trim();
        return (v == null || v.isEmpty) ? null : v;
        }

        // 简介:取详情页正文面板(.text-area.common-text)的全部富文本 HTML,
        // 即完整的“模组介绍”内容;页面没有该面板时回退到搜索页 wiki 简介
        final description =
            _extractFullContentHtml(doc) ?? _bbcodeToHtml(fallbackDescription ?? '');

        return ModDetail(
        id: id,
        title: title,
        subName: subName,
        description: description.isEmpty ? null : description,
        coverUrl: coverUrl,
        links: links,
        mcVersions: mcVersions,
        platform: field('支持平台'),
        environment: field('运行环境'),
        );
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
        // 图片:去掉固定宽高与 class,限制最大宽度防止溢出屏幕;
        // 包一层链接,点击图片时在灯箱中放大查看
        s = s.replaceAllMapped(RegExp(r'<img([^>]*)>'), (m) {
        final attrs = m.group(1)!;
        final src = RegExp(r'src="([^"]*)"').firstMatch(attrs)?.group(1);
        final cleaned = attrs
            .replaceAll(RegExp(r'\s+(width|height)="[^"]*"'), '')
            .replaceAll(RegExp(r'\s+(class|style)="[^"]*"'), '');
        final img = '<img$cleaned style="max-width:100%">';
        return (src == null || src.isEmpty)
            ? img
            : '<a href="$src">$img</a>';
        });
        // 表格分类处理:
        // - 含图片的表格(截图画廊等):转成纵向堆叠的 div 布局。
        //   fwfh 的表格布局在单元格含图片时,计算 dry-baseline 会访问
        //   RenderImage 的 size,触发 Flutter 断言崩溃;竖排也更适合窄屏。
        // - 纯文字的表格(按键说明、元素表等):保留表格渲染,仅清理固定宽度。
        s = s.replaceAllMapped(
        RegExp(r'<table[^>]*>.*?</table>', dotAll: true),
        (m) {
            final block = m.group(0)!;
            if (block.contains('<img')) return _tableToDiv(block);
            return block
                .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
                .replaceAll(RegExp(r'\s+style="[^"]*"'), '');
        },
        );
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

    /// 把含图片的表格转成纵向堆叠的 div 布局(内容完整保留)
    static String _tableToDiv(String block) {
        return block.replaceAllMapped(
        RegExp(r'</?(?:table|tbody|thead|tr|td|th)[^>]*>'),
        (m) {
            final tag = m.group(0)!;
            final closing = tag.startsWith('</');
            final name = tag
                .substring(closing ? 2 : 1)
                .split(RegExp(r'[\s>]'))
                .first;
            if (closing) return '</div>';
            return switch (name) {
            'td' || 'th' => '<div style="padding:4px 0">',
            _ => '<div>',
            };
        },
        );
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
            RegExp('\\[$tag\\](.*?)\\[/$tag\\]', dotAll: true, caseSensitive: false),
            (m) => '${entry.value.$1}${m.group(1)}${entry.value.$2}',
        );
        }
        // [color=xxx]..[/color]
        s = s.replaceAllMapped(
        RegExp(r'\[color=([^\]]*)\](.*?)\[/color\]', dotAll: true,
            caseSensitive: false),
        (m) => '<span style="color:${m.group(1)}">${m.group(2)}</span>',
        );
        // [url=xxx]label[/url] 与 [url]xxx[/url]
        s = s.replaceAllMapped(
        RegExp(r'\[url=([^\]]*)\](.*?)\[/url\]', dotAll: true,
            caseSensitive: false),
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
        final items = content.split('[*]').map((e) => e.trim()).where((e) => e.isNotEmpty);
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
