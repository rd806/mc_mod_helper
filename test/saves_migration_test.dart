import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/model/project/project_summary.dart';
import 'package:mc_mod_helper/model/project/project_type.dart';
import 'package:mc_mod_helper/service/saves/history.dart';
import 'package:mc_mod_helper/service/saves/likes.dart';
import 'package:mc_mod_helper/setting/value/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 老版本的收藏库(v2:还没有 type 列)。
/// 用户从 1.1.0 升级上来时,库里就是这样的数据
Future<void> _legacyLikesDb(String path) async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE likes(
          id TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          sub_name TEXT,
          icon_url TEXT,
          source TEXT NOT NULL,
          date REAL NOT NULL,
          PRIMARY KEY(source, id)
        )'''),
    ),
  );
  await db.insert('likes', {
    'id': '459',
    'title': '[JEI] JEI物品管理器',
    'sub_name': 'Just Enough Items',
    'source': 'mcmod',
    'date': 1725500000000.0,
  });
  await db.close();
}

/// 老版本的浏览历史库(v1:还没有 type 列)
Future<void> _legacyHistoryDb(String path) async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => db.execute('''
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
        )'''),
    ),
  );
  await db.insert('history', {
    'id': '459',
    'title': '[JEI] JEI物品管理器',
    'source': 'mcmod',
    'date': 1725500000000.0,
    'visits': 3,
  });
  await db.close();
}

ProjectSummary _summary(ProjectType type) => ProjectSummary(
  id: 'pack',
  type: type,
  title: '整合包',
  description: '',
  source: ModSource.modrinth,
);

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('收藏库升级:旧记录(无 type 列)读出来是模组,新写入的类型能存住', () async {
    final dir = await Directory.systemTemp.createTemp('mcmodhelper_migrate');
    final path = '${dir.path}/favorites.db';
    await _legacyLikesDb(path);

    // 打开时走到 v3:补上 type 列
    await FavoritesService.instance.init(dbPath: path);
    final legacy = FavoritesService.instance.list().single;
    expect(legacy.id, '459');
    expect(legacy.subName, 'Just Enough Items'); // 更早那次升级的列也在
    expect(legacy.type, ProjectType.mod);
    expect(legacy.toSummary().type, ProjectType.mod);

    // 升级之后写入的记录带着自己的类型,并能从库里读回来
    await FavoritesService.instance.add(
      Likes.fromSummary(_summary(ProjectType.modpack), time: DateTime.now()),
    );
    expect(FavoritesService.instance.list().first.type, ProjectType.modpack);
    expect(
      FavoritesService.instance.summaries().first.type,
      ProjectType.modpack,
    );
  });

  test('浏览历史库升级:旧记录读出来是模组,浏览次数不受影响', () async {
    final dir = await Directory.systemTemp.createTemp('mcmodhelper_migrate');
    final path = '${dir.path}/history.db';
    await _legacyHistoryDb(path);

    await HistoryService.instance.init(dbPath: path);
    final legacy = HistoryService.instance.list().single;
    expect(legacy.visits, 3);
    expect(legacy.type, ProjectType.mod);

    await HistoryService.instance.record(_summary(ProjectType.modpack));
    expect(HistoryService.instance.list().first.type, ProjectType.modpack);
    expect(HistoryService.instance.summaries().first.type, ProjectType.modpack);
  });
}
