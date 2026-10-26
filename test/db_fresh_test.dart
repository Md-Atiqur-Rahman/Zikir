import 'dart:io';

import 'package:digital_tasbih/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zikir_fresh');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'fresh database has the 20 zikirs with the requested targets and beeps',
    () async {
      final cats = await Db.categories();
      expect(cats.length, 20);

      // goal / beep from the owner's list
      for (var i = 0; i < 5; i++) {
        expect(
          (cats[i].goal, cats[i].beepEvery),
          (100, 25),
          reason: 'zikir ${i + 1}',
        );
      }
      for (final i in [5, 6, 7, 8, 10, 11, 12, 13, 14, 15]) {
        expect(
          (cats[i].goal, cats[i].beepEvery),
          (21, 12),
          reason: 'zikir ${i + 1}',
        );
      }
      expect((cats[9].goal, cats[9].beepEvery), (100, 25));
      for (final i in [16, 17, 18, 19]) {
        expect(
          (cats[i].goal, cats[i].beepEvery),
          (10, 0),
          reason: 'zikir ${i + 1}',
        );
      }
      expect(cats.every((c) => c.meaning.isNotEmpty), isTrue);
    },
  );

  test('bulk import defaults match the owner list', () async {
    final cats = await Db.categories();
    final want = [
      ...List.filled(5, 100),
      ...List.filled(4, 21),
      100,
      ...List.filled(5, 21),
      ...List.filled(5, 10),
    ];
    expect([for (final c in cats) defaultBulkCount(c.name)], want);
    expect(defaultBulkCount('some custom zikir'), 0);
  });

  test(
    'bulkAdd fills every day of the range and adds on top of existing counts',
    () async {
      final cats = await Db.categories();
      final a = cats[0].id, b = cats[1].id;
      await Db.bulkAdd(DateTime(2026, 9, 20), DateTime(2026, 9, 22), {
        a: 100,
        b: 50,
      }, 'ফজর');
      expect(await Db.dayTotal('2026-09-20'), 150);
      expect(await Db.dayTotal('2026-09-22'), 150);
      expect(await Db.dayTotal('2026-09-23'), 0);
      expect(await Db.doneCount('2026-09-21', 'ফজর'), 2);
      expect(await Db.doneCount('2026-09-21', 'জোহর'), 0);
      expect(await Db.rangeTotal('2026-09-20', '2026-09-22'), 450);

      await Db.bulkAdd(DateTime(2026, 9, 21), DateTime(2026, 9, 21), {
        a: 10,
      }, 'ফজর');
      expect(await Db.dayTotal('2026-09-21'), 160);

      final rows = await Db.dayRows('2026-09-20');
      expect(rows.map((r) => (r.prayer, r.count)).toSet(), {
        ('ফজর', 100),
        ('ফজর', 50),
      });
      expect((await Db.monthTotals()).first, ('2026-09', 460));
    },
  );
}
