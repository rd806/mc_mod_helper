import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:mc_mod_helper/model/mod/mod_summary.dart';
import 'package:mc_mod_helper/service/value/source.dart';
import 'package:path/path.dart' as p;
// 副作用导入:sqflite 库加载时把插件工厂设为默认工厂
// (databaseFactoryOrNull ??= 插件工厂),移动端(Android/iOS)靠它
// 拿到平台通道实现;使用的符号都来自 sqflite_common,故按 lint 忽略
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 浏览历史条目(纯数据,与存储后端无关)。
///
/// 与收藏一样只存列表页/详情页跳转所需的摘要字段,外加一个访问次数:
/// 反复打开同一个模组只留一条记录,不会把列表刷满。
class History {
  History({
    required this.id,
    required this.title,
    this.description,
    this.subName,
    this.iconUrl,
    ModSource source = ModSource.mcmod,
    required this.date,
    this.visits = 1,
  }) : sourceName = source.name;

  /// 统一模组标识(字符串):MC百科为数字字符串,Modrinth 为 slug
  final String id;

  final String title;

  /// 次要名称(如英文名)
  final String? subName;
  final String? description;
  final String? iconUrl;

  /// 数据来源的枚举名(存 name 而非 index:枚举增删/改序后旧数据不失效)
  final String sourceName;

  /// 最近一次浏览时间(Unix 时间戳,毫秒)
  final double date;

  /// 累计浏览次数
  final int visits;

  /// 从列表页/详情页摘要构造
  factory History.fromSummary(
    ModSummary mod, {
    required DateTime time,
    int visits = 1,
  }) {
    return History(
      id: mod.id,
      title: mod.title,
      description: mod.description,
      subName: mod.subName,
      iconUrl: mod.iconUrl,
      source: mod.source,
      date: time.millisecondsSinceEpoch.toDouble(),
      visits: visits,
    );
  }

  /// 数据来源(由持久化的枚举名还原,未知值回落到 mcmod)
  ModSource get source => SourceManager.sourceToString(sourceName);

  /// 最近浏览时间
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(date.round());

  /// 转成列表页可用的摘要
  ModSummary toSummary() => ModSummary(
    id: id,
    title: title,
    description: description ?? '',
    subName: subName,
    iconUrl: iconUrl,
    source: source,
  );

  History copyWith({DateTime? time, int? visits}) => History(
    id: id,
    title: title,
    description: description,
    subName: subName,
    iconUrl: iconUrl,
    source: source,
    date: (time ?? this.time).millisecondsSinceEpoch.toDouble(),
    visits: visits ?? this.visits,
  );
}

/// 浏览历史服务:单例,SQLite 持久化 + 内存缓存。
///
/// 与收藏服务同构(见 FavoritesService):启动时 [init],
/// 详情页加载成功后调用 [record] 记一次浏览;页面用 ListenableBuilder
/// 监听实现响应式刷新。最多保留 [maxEntries] 条,超出丢弃最旧的。
class HistoryService extends ChangeNotifier {
  HistoryService._();

  /// 全局唯一实例
  static final HistoryService instance = HistoryService._();

  /// 保留的最大条数(超出丢弃最旧的)
  static const int maxEntries = 200;

  /// 建表语句(PRIMARY KEY(source, id):多来源下按复合键去重)
  static const String _createSql = '''
    CREATE TABLE history(
      id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      sub_name TEXT,
      icon_url TEXT,
      source TEXT NOT NULL,
      date REAL NOT NULL,
      visits INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY(source, id)
    )''';

  Database? _db;

  /// 内存缓存(与数据库同步;UI 读走缓存,不查库)
  List<History> _cache = [];

  /// 初始化:按平台切换数据库工厂、打开(或创建)数据库并加载缓存。
  ///
  /// - 桌面(Windows/Linux)与测试环境:切换 FFI 实现(见 [_ensureDesktopFactory]);
  /// - 移动端(Android/iOS):使用 sqflite 插件工厂(默认工厂,无需配置)。
  ///
  /// [dbPath] 供测试传入临时目录;不传时用平台默认数据库目录。
  Future<void> init({String? dbPath}) async {
    _ensureDesktopFactory();
    final path =
        dbPath ??
        p.join(await databaseFactory.getDatabasesPath(), 'history.db');
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute(_createSql),
      ),
    );
    final rows = await _db!.query('history', orderBy: 'date DESC');
    _cache = [for (final row in rows) _fromRow(row)];
  }

  /// 浏览历史(按最近浏览时间倒序)
  List<History> list() => List.unmodifiable(_cache);

  /// 浏览历史的摘要(列表页直接渲染)
  List<ModSummary> summaries() => [for (final h in _cache) h.toSummary()];

  /// 记录一次浏览。
  ///
  /// 同一个模组已有记录时只更新时间与次数并置顶(不重复插入);
  /// 先更新缓存让界面立即响应,再异步落库
  Future<void> record(ModSummary mod, {DateTime? time}) async {
    final at = time ?? DateTime.now();
    final index = _cache.indexWhere(
      (h) => h.id == mod.id && h.sourceName == mod.source.name,
    );
    final entry = index >= 0
        // 复用旧记录的访问次数;标题等用最新一次的数据补齐
        ? _cache[index].copyWith(time: at, visits: _cache[index].visits + 1)
        : History.fromSummary(mod, time: at);
    _cache
      ..removeWhere((h) => h.id == mod.id && h.sourceName == mod.source.name)
      ..insert(0, entry);
    _trim();
    notifyListeners();
    await _insert(entry);
    await _trimDb();
  }

  /// 删除某条记录(未记录时无操作)
  Future<void> remove(ModSummary mod) async {
    final before = _cache.length;
    _cache.removeWhere(
      (h) => h.id == mod.id && h.sourceName == mod.source.name,
    );
    if (_cache.length == before) return;
    notifyListeners();
    await _db!.delete(
      'history',
      where: 'id = ? AND source = ?',
      whereArgs: [mod.id, mod.source.name],
    );
  }

  /// 清空全部浏览历史(界面的「清空历史」与测试用例隔离用)
  Future<void> clear() async {
    if (_cache.isEmpty) return;
    _cache = [];
    notifyListeners();
    await _db!.delete('history');
  }

  /// 缓存裁剪到 [maxEntries] 条
  void _trim() {
    if (_cache.length > maxEntries) {
      _cache = _cache.sublist(0, maxEntries);
    }
  }

  /// 落库:同一个模组覆盖写入(upsert)
  Future<void> _insert(History entry) async {
    await _db!.insert('history', {
      'id': entry.id,
      'title': entry.title,
      'description': entry.description,
      'sub_name': entry.subName,
      'icon_url': entry.iconUrl,
      'source': entry.sourceName,
      'date': entry.date,
      'visits': entry.visits,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 数据库同步裁剪:删掉超出上限的最旧记录
  Future<void> _trimDb() async {
    await _db!.rawDelete(
      'DELETE FROM history WHERE rowid NOT IN '
      '(SELECT rowid FROM history ORDER BY date DESC LIMIT ?)',
      [maxEntries],
    );
  }

  /// 桌面平台(Windows/Linux)与测试环境没有 sqflite 平台通道,
  /// 切换到 FFI 实现(NoIsolate 版本:同 isolate 内同步 FFI 调用,
  /// 后台 isolate 的响应在 widget 测试的假时钟里永远等不到完成)
  void _ensureDesktopFactory() {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }

  static History _fromRow(Map<String, Object?> row) => History(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description'] as String?,
    subName: row['sub_name'] as String?,
    iconUrl: row['icon_url'] as String?,
    source: SourceManager.sourceToString(row['source'] as String?),
    date: (row['date']! as num).toDouble(),
    visits: (row['visits'] as num?)?.toInt() ?? 1,
  );
}
