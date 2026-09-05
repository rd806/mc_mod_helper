import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/value/source.dart';
import 'package:mc_mod_helper/model/mod_summary.dart';
import 'package:mc_mod_helper/service/savings.dart';

void main() {
  setUpAll(() async {
    // 单例一次初始化:临时目录里的 SQLite 数据库
    final dir = await Directory.systemTemp.createTemp(
      'mcmodhelper_sqlite_test',
    );
    await FavoritesService.instance.init(dbPath: '${dir.path}/favorites.db');
  });

  setUp(() async {
    // 用例间隔离:清空收藏
    await FavoritesService.instance.clear();
  });

  test('Likes 完整写读还原(含枚举与时间戳)', () async {
    await FavoritesService.instance.add(
      Likes(
        id: '459',
        title: '[JEI] JEI物品管理器',
        description: '查看物品的合成与用途',
        subName: 'Just Enough Items',
        iconUrl: 'https://i.mcmod.cn/jei.png',
        source: ModSource.mcmod,
        date: 1725500000000.0,
      ),
    );

    final read = FavoritesService.instance.list().single;
    expect(read.id, '459');
    expect(read.title, contains('JEI'));
    expect(read.subName, 'Just Enough Items');
    expect(read.iconUrl, 'https://i.mcmod.cn/jei.png');
    expect(read.source, ModSource.mcmod);
    expect(read.time.millisecondsSinceEpoch, 1725500000000);
    // 摘要还原:次要名称与页面地址
    expect(read.toSummary().subName, 'Just Enough Items');
    expect(read.toSummary().pageUrl, 'https://www.mcmod.cn/class/459.html');
  });

  test('modrinth 来源的收藏也完整还原', () async {
    await FavoritesService.instance.add(
      Likes(
        id: 'jei',
        title: 'JEI',
        description: 'Just Enough Items',
        source: ModSource.modrinth,
        date: 1725500001000.0,
      ),
    );

    expect(FavoritesService.instance.list().single.source, ModSource.modrinth);
    expect(
      FavoritesService.instance.summaries().single.pageUrl,
      'https://modrinth.com/mod/jei',
    );
  });

  test('add 同「来源+id」去重,remove/isFavorite 按复合键匹配', () async {
    final mod = ModSummary(
      id: '1',
      title: 'A',
      description: '',
      source: ModSource.mcmod,
    );
    await FavoritesService.instance.add(
      Likes(id: '1', title: 'A', description: '', date: 1.0),
    );
    // 同 id 再次收藏:不重复写入
    await FavoritesService.instance.add(
      Likes(id: '1', title: 'A', description: '', date: 2.0),
    );
    expect(FavoritesService.instance.list(), hasLength(1));
    expect(FavoritesService.instance.isFavorite(mod), isTrue);

    // 不同来源的同名 id 不互相影响(modrinth slug 可能与数字 id 相同)
    final other = ModSummary(
      id: '1',
      title: 'A',
      description: '',
      source: ModSource.modrinth,
    );
    expect(FavoritesService.instance.isFavorite(other), isFalse);

    await FavoritesService.instance.remove(mod);
    expect(FavoritesService.instance.list(), isEmpty);
    expect(FavoritesService.instance.isFavorite(mod), isFalse);
  });

  test('toggle 收藏开关:加入/移除', () async {
    final mod = ModSummary(
      id: '459',
      title: 'JEI',
      description: '',
      source: ModSource.mcmod,
    );
    await FavoritesService.instance.toggle(mod);
    expect(FavoritesService.instance.isFavorite(mod), isTrue);

    await FavoritesService.instance.toggle(mod);
    expect(FavoritesService.instance.isFavorite(mod), isFalse);
  });

  test('list 按收藏时间倒序', () async {
    await FavoritesService.instance.add(
      Likes(id: 'old', title: '旧', description: '', date: 1.0),
    );
    await FavoritesService.instance.add(
      Likes(id: 'new', title: '新', description: '', date: 2.0),
    );
    expect(FavoritesService.instance.list().map((l) => l.id), ['new', 'old']);
  });
}
