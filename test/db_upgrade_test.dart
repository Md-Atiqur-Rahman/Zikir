import 'dart:io';

import 'package:digital_tasbih/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An installed v4 database (old defaults, user data) must upgrade to v5 without losing counts.
void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zikir_upgrade');
    await databaseFactory.setDatabasesPath(dir.path);

    final old = await openDatabase(
      p.join(dir.path, 'tasbih.db'),
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL,
          target TEXT NOT NULL DEFAULT '', meaning TEXT NOT NULL DEFAULT '',
          goal INTEGER NOT NULL DEFAULT 0, beep_every INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE entries(
          category_id INTEGER NOT NULL, date TEXT NOT NULL,
          prayer TEXT NOT NULL DEFAULT '', count INTEGER NOT NULL,
          PRIMARY KEY (category_id, date, prayer))''');
        await db.execute('''CREATE TABLE prayers(
          name TEXT PRIMARY KEY, ord INTEGER NOT NULL,
          start_min INTEGER NOT NULL, end_min INTEGER NOT NULL)''');
        // a default zikir with the OLD values, and a custom one the owner made
        await db.insert('categories', {
          'name': 'আস্তাগফিরুল্লাহ',
          'target': '100',
          'goal': 100,
          'beep_every': 20,
          'sort_order': 1,
        });
        await db.insert('categories', {
          'name': 'My custom zikir',
          'target': '33',
          'goal': 33,
          'beep_every': 11,
          'sort_order': 2,
        });
        await db.insert('entries', {
          'category_id': 1,
          'date': '2026-10-01',
          'prayer': 'ফজর',
          'count': 77,
        });
      },
    );
    await old.close();
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'v4 -> v5 keeps data, applies new defaults to built-in zikirs only',
    () async {
      final cats = await Db.categories();
      final istighfar = cats.firstWhere((c) => c.name == 'আস্তাগফিরুল্লাহ');
      expect((istighfar.goal, istighfar.beepEvery), (100, 25)); // was beep 20
      expect(istighfar.total, 77); // saved count survived

      final custom = cats.firstWhere((c) => c.name == 'My custom zikir');
      expect((custom.goal, custom.beepEvery), (33, 11)); // untouched

      expect(await Db.grandTotal(), 77);
      expect(await Db.doneCount('2026-10-01', 'ফজর'), 1);
    },
  );
}
