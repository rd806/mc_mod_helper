import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:mc_mod_helper/value/source.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';
import 'package:path/path.dart' as p;
// 副作用导入:sqflite 库加载时把插件工厂设为默认工厂
// (databaseFactoryOrNull ??= 插件工厂),移动端(Android/iOS)靠它
// 拿到平台通道实现;使用的符号都来自 sqflite_common,故按 lint 忽略
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 收藏的模组条目(纯数据,与存储后端无关)。
///
/// 只存列表页展示与跳详情所需的摘要字段,
/// 而不是整个 ModDetail(详情接口数据量大,收藏只需要摘要)。
class Likes {
  Likes({
    required this.id,
    required this.title,
    required this.description,
    this.subName,
    this.iconUrl,
    ModSource source = ModSource.mcmod,
    required this.date,
  }) : sourceName = source.name;

  final String id;
  final String title;
  final String description;

  /// 次要名称(如英文名),收藏页卡片副标题用
  final String? subName;
  final String? iconUrl;

  /// 数据来源的枚举名(如 'modrinth')。
  ///
  /// 存 name 字符串而非枚举 index:枚举增删/改序后旧数据不失效
  final String sourceName;

  /// 收藏时间(Unix 时间戳,毫秒)
  final double date;

  /// 从列表页摘要构造(收藏入口拿到的通常是 ModSummary)
  factory Likes.fromSummary(ModSummary mod, {required DateTime time}) {
    return Likes(
      id: mod.id,
      title: mod.title,
      description: mod.description,
      subName: mod.subName,
      iconUrl: mod.iconUrl,
      source: mod.source,
      date: time.millisecondsSinceEpoch.toDouble(),
    );
  }

  /// 数据来源(由持久化的枚举名还原,未知值回落到 mcmod)
  ModSource get source => SourceManager.sourceToString(sourceName);

  /// 收藏时间(由时间戳还原)
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(date.round());

  /// 转成列表页可用的摘要
  ModSummary toSummary() => ModSummary(
    id: id,
    title: title,
    description: description,
    subName: subName,
    iconUrl: iconUrl,
    source: source,
  );
}

/// 收藏服务:单例,SQLite 持久化 + 内存缓存。
///
/// 启动时调用 [init](桌面端自动切换 FFI 实现并建表),
/// 之后通过 [isFavorite]/[add]/[remove]/[toggle] 读写;
/// 服务本身是 ChangeNotifier,收藏变化时通知,
/// 心形按钮/收藏页用 ListenableBuilder 监听实现响应式刷新。
class FavoritesService extends ChangeNotifier {
  FavoritesService._();

  /// 全局唯一实例
  static final FavoritesService instance = FavoritesService._();

  /// 建表语句(PRIMARY KEY(source, id):多来源下按复合键去重)
  static const String _createSql = '''
    CREATE TABLE likes(
      id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      sub_name TEXT,
      icon_url TEXT,
      source TEXT NOT NULL,
      date REAL NOT NULL,
      PRIMARY KEY(source, id)
    )''';

  Database? _db;

  /// 内存缓存(与数据库同步;UI 读走缓存,不查库)
  List<Likes> _cache = [];

  /// 初始化:按平台切换数据库工厂、打开(或创建)数据库并加载缓存。
  ///
  /// - 桌面(Windows/Linux)与测试环境:切换 FFI 实现(见 [_ensureDesktopFactory]);
  /// - 移动端(Android/iOS):使用 sqflite 插件工厂(默认工厂,无需配置)。
  ///
  /// [dbPath] 供测试传入临时目录;不传时用平台默认数据库目录。
  /// 重复调用安全(数据库已打开时直接复用)
  Future<void> init({String? dbPath}) async {
    _ensureDesktopFactory();
    final path =
        dbPath ??
        p.join(await databaseFactory.getDatabasesPath(), 'favorites.db');
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => db.execute(_createSql),
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 → v2:新增次要名称列
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE likes ADD COLUMN sub_name TEXT');
          }
        },
      ),
    );
    final rows = await _db!.query('likes', orderBy: 'date DESC');
    _cache = [for (final row in rows) _fromRow(row)];
  }

  /// 是否已收藏。
  ///
  /// 匹配按「来源 + id」复合键:各来源的 id 规则不同
  /// (MC百科数字字符串 / Modrinth slug),只按 id 可能误伤
  bool isFavorite(ModSummary mod) =>
      _cache.any((l) => l.id == mod.id && l.sourceName == mod.source.name);

  /// 收藏(返回保存的条目);已收藏时返回 null 不重复写入。
  ///
  /// 先更新缓存让 UI 立即响应,再异步落库(乐观更新);
  /// 落库失败时回滚缓存
  Future<Likes?> add(Likes likes) async {
    if (_cache.any(
      (l) => l.id == likes.id && l.sourceName == likes.sourceName,
    )) {
      return null;
    }
    _cache.add(likes);
    _cache.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    try {
      await _db!.insert('likes', {
        'id': likes.id,
        'title': likes.title,
        'description': likes.description,
        'sub_name': likes.subName,
        'icon_url': likes.iconUrl,
        'source': likes.sourceName,
        'date': likes.date,
      });
    } catch (_) {
      _cache.removeWhere(
        (l) => l.id == likes.id && l.sourceName == likes.sourceName,
      );
      notifyListeners();
    }
    return likes;
  }

  /// 取消收藏(未收藏时无操作)。
  ///
  /// 与 [add] 一致:先更新缓存(乐观更新)再异步落库
  Future<void> remove(ModSummary mod) async {
    _cache.removeWhere(
      (l) => l.id == mod.id && l.sourceName == mod.source.name,
    );
    notifyListeners();
    await _db!.delete(
      'likes',
      where: 'id = ? AND source = ?',
      whereArgs: [mod.id, mod.source.name],
    );
  }

  /// 收藏开关:已收藏则取消,未收藏则加入(收藏按钮直接调用)
  Future<void> toggle(ModSummary mod) async {
    if (isFavorite(mod)) {
      await remove(mod);
    } else {
      await add(Likes.fromSummary(mod, time: DateTime.now()));
    }
  }

  /// 收藏列表(按收藏时间倒序)
  List<Likes> list() => List.unmodifiable(_cache);

  /// 收藏列表的摘要(列表页直接渲染)
  List<ModSummary> summaries() => [for (final l in _cache) l.toSummary()];

  /// 清空收藏(测试用例间隔离用)
  @visibleForTesting
  Future<void> clear() async {
    await _db!.delete('likes');
    _cache.clear();
    notifyListeners();
  }

  /// 桌面平台(Windows/Linux)与测试环境没有 sqflite 平台通道,
  /// 切换到 FFI 实现(NoIsolate 版本:同 isolate 内同步 FFI 调用)。
  ///
  /// 收藏表的写入很小,不需要后台 isolate;后台 isolate 的响应是
  /// 真实异步,在 widget 测试的假时钟里永远等不到完成,
  /// 其写事务的超时计时器会残留成 pending Timer。
  /// Windows 上 sqlite3 包优先加载 sqlite3.dll,
  /// 缺失时自动回退系统自带的 winsqlite3.dll
  void _ensureDesktopFactory() {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }

  static Likes _fromRow(Map<String, Object?> row) => Likes(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    subName: row['sub_name'] as String?,
    iconUrl: row['icon_url'] as String?,
    source: SourceManager.sourceToString(row['source'] as String?),
    date: (row['date']! as num).toDouble(),
  );
}
