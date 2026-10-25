import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Category {
  final int id;
  final String name;
  final String target; // suggested count, free text like "100" or "1-100"
  final String meaning; // Bangla meaning shown under the zikir
  final int goal; // target count; 0 = none
  final int beepEvery; // beep every N counts; 0 = never
  final int total;
  Category(
    this.id,
    this.name,
    this.target,
    this.meaning,
    this.goal,
    this.beepEvery,
    this.total,
  );

  /// What to show as the suggested count: the numeric goal, else the free-text note.
  String get targetLabel => goal > 0 ? '$goal' : target;
}

class DayEntry {
  final String date; // yyyy-MM-dd
  final String prayer; // '' when outside every prayer window
  final int count;
  DayEntry(this.date, this.prayer, this.count);
}

class Prayer {
  final String name;
  final int ord;
  int startMin;
  int endMin;
  Prayer(this.name, this.ord, this.startMin, this.endMin);

  /// [m] is minutes since midnight. A window may cross midnight (start > end).
  bool contains(int m) => startMin <= endMin
      ? (m >= startMin && m < endMin)
      : (m >= startMin || m < endMin);
}

String prayerAt(List<Prayer> prayers, DateTime t) {
  final m = t.hour * 60 + t.minute;
  for (final p in prayers) {
    if (p.contains(m)) return p.name;
  }
  return '';
}

const _defaultZikirs = <(String, String)>[
  ('সুবহানাল্লাহ', ''),
  ('আলহামদুলিল্লাহ', ''),
  ('আল্লাহু আকবার', ''),
  ('লা ইলাহা ইল্লাল্লাহু', ''),
  ('আস্তাগফিরুল্লাহ', '100'),
  ('লা হাওলা ওয়ালা কুওয়াতা ইল্লা বিল্লাহিল আলিউল আজিম', '21'),
  ('আস্তাগফিরুল্লাহ ইন্নাল্লাহা গাফুরুর রাহিম', '21'),
  ('আল্লাহুম্মা সাল্লি ওয়া সাল্লিম ‘আলা নাবিয়্যিনা মুহাম্মাদ', '21'),
  ('রাব্বি ইন্নি লিমা আনজালতা ইলাইয়্যা মিন খাইরিন ফাকির', '1-100'),
  ('সুবহানাল্লাহি ওয়া বিহামদিহি, সুবহানাল্লাহিল আজিম', '1-100'),
  ('লা ইলাহা ইল্লা আনতা সুবহানাকা ইন্নী কুনতু মিনায যলিমীন', '21'),
  (
    'আস্তাগফিরুল্লাহ হাল্লাজি লা ইলাহা ইল্লা হুয়াল হাইয়ুল কাইয়ুম ওয়াতুবু ইলাইহি',
    '21',
  ),
  ('আল্লাহুম্মা সাল্লি আলা মুহাম্মাদিন সাল্লাল্লাহু আলাইহি ওয়াসাল্লাম', ''),
  ('আল্লাহুম্মাগফিরলি', ''),
  ('হাসবুনাল্লাহু ওয়া নি’মাল ওয়াকিল', ''),
  ('ইয়া হাইয়ু ইয়া কাইয়ুম ইয়া জালজালালি ওয়াল ইকরাম', ''),
  ('আল্লাহুম্মার হামনি বিরাহমতিকা ইয়া আরহামার রাহিমিন', ''),
  ('সালামুন কাওলাম মির রাব্বির রাহিম', ''),
  ('আল্লাহুম্মা খাইরান ফী কুল্লি আমরিন আন্তাজিরুহ', ''),
  ('রাব্বি আন্নি মাসসানিয়াদ দুররু ওয়া আনতা আরহামুর রাহিমিন', ''),
];

// Bangla meaning for each default zikir, keyed by its name.
const _defaultMeanings = <String, String>{
  'সুবহানাল্লাহ': 'আল্লাহ পবিত্র।',
  'আলহামদুলিল্লাহ': 'সকল প্রশংসা আল্লাহর জন্য।',
  'আল্লাহু আকবার': 'আল্লাহ সবচেয়ে মহান।',
  'লা ইলাহা ইল্লাল্লাহু': 'আল্লাহ ছাড়া কোনো ইলাহ (উপাস্য) নেই।',
  'আস্তাগফিরুল্লাহ': 'আমি আল্লাহর কাছে ক্ষমা চাচ্ছি।',
  'লা হাওলা ওয়ালা কুওয়াতা ইল্লা বিল্লাহিল আলিউল আজিম': 'মহান ও সর্বোচ্চ আল্লাহর সাহায্য ছাড়া (গুনাহ থেকে বাঁচার) কোনো উপায় এবং (ভালো কাজ করার) কোনো শক্তি নেই।',
  'আস্তাগফিরুল্লাহ ইন্নাল্লাহা গাফুরুর রাহিম': 'আমি আল্লাহর কাছে ক্ষমা চাচ্ছি; নিশ্চয়ই আল্লাহ অত্যন্ত ক্ষমাশীল, পরম দয়ালু।',
  'আল্লাহুম্মা সাল্লি ওয়া সাল্লিম ‘আলা নাবিয়্যিনা মুহাম্মাদ':
      'হে আল্লাহ, আমাদের নবী মুহাম্মাদ (সাঃ)-এর উপর রহমত ও শান্তি বর্ষণ করুন।',
  'রাব্বি ইন্নি লিমা আনজালতা ইলাইয়্যা মিন খাইরিন ফাকির': 'হে আমার রব, আপনি আমার প্রতি যে কল্যাণই নাজিল করবেন, আমি তার মুখাপেক্ষী। (সূরা কাসাস ২৮:২৪)',
  'সুবহানাল্লাহি ওয়া বিহামদিহি, সুবহানাল্লাহিল আজিম':
      'আল্লাহ পবিত্র ও তাঁর প্রশংসা করছি; মহান আল্লাহ পবিত্র।',
  'লা ইলাহা ইল্লা আনতা সুবহানাকা ইন্নী কুনতু মিনায যলিমীন': 'আপনি ছাড়া কোনো ইলাহ নেই, আপনি পবিত্র; নিশ্চয়ই আমি জালিমদের অন্তর্ভুক্ত ছিলাম। (সূরা আম্বিয়া ২১:৮৭)',
  'আস্তাগফিরুল্লাহ হাল্লাজি লা ইলাহা ইল্লা হুয়াল হাইয়ুল কাইয়ুম ওয়াতুবু ইলাইহি': 'আমি সেই আল্লাহর কাছে ক্ষমা চাচ্ছি, যিনি ছাড়া কোনো ইলাহ নেই; তিনি চিরঞ্জীব, সবকিছুর ধারক; আর আমি তাঁর কাছে তওবা করছি।',
  'আল্লাহুম্মা সাল্লি আলা মুহাম্মাদিন সাল্লাল্লাহু আলাইহি ওয়াসাল্লাম': 'হে আল্লাহ, মুহাম্মাদ (সাঃ)-এর উপর রহমত বর্ষণ করুন; তাঁর উপর আল্লাহর রহমত ও শান্তি বর্ষিত হোক।',
  'আল্লাহুম্মাগফিরলি': 'হে আল্লাহ, আমাকে ক্ষমা করুন।',
  'হাসবুনাল্লাহু ওয়া নি’মাল ওয়াকিল':
      'আল্লাহই আমাদের জন্য যথেষ্ট, আর তিনিই উত্তম কর্মবিধায়ক।',
  'ইয়া হাইয়ু ইয়া কাইয়ুম ইয়া জালজালালি ওয়াল ইকরাম':
      'হে চিরঞ্জীব, হে সবকিছুর ধারক, হে মহিমা ও সম্মানের অধিকারী।',
  'আল্লাহুম্মার হামনি বিরাহমতিকা ইয়া আরহামার রাহিমিন':
      'হে আল্লাহ, আপনার রহমতে আমার প্রতি দয়া করুন, হে সর্বশ্রেষ্ঠ দয়ালু।',
  'সালামুন কাওলাম মির রাব্বির রাহিম': 'পরম দয়ালু রবের পক্ষ থেকে (তাদের উদ্দেশে) বলা হবে ‘সালাম’ (শান্তি)। (সূরা ইয়াসিন ৩৬:৫৮)',
  'আল্লাহুম্মা খাইরান ফী কুল্লি আমরিন আন্তাজিরুহ': 'হে আল্লাহ, আমি যে বিষয়ের অপেক্ষায় আছি, তার প্রতিটিতে আমাকে কল্যাণ দান করুন।',
  'রাব্বি আন্নি মাসসানিয়াদ দুররু ওয়া আনতা আরহামুর রাহিমিন': 'হে আমার রব, আমাকে কষ্ট স্পর্শ করেছে, আর আপনি সর্বশ্রেষ্ঠ দয়ালু। (সূরা আম্বিয়া ২১:৮৩)',
};

// Beep every N counts, for the default zikirs that have one.
const _defaultBeepEvery = <String, int>{'আস্তাগফিরুল্লাহ': 20};

// name, start, end in minutes since midnight
const _defaultPrayers = <(String, int, int)>[
  ('ফজর', 5 * 60, 7 * 60),
  ('ইশরাক', 7 * 60, 9 * 60),
  ('চাশত', 9 * 60, 11 * 60 + 30),
  ('জোহর', 13 * 60, 16 * 60),
  ('আসর', 16 * 60, 17 * 60 + 15),
  ('মাগরিব', 17 * 60 + 20, 19 * 60),
  ('ইশা', 19 * 60 + 30, 2 * 60),
  ('তাহাজ্জুদ', 3 * 60, 4 * 60),
];

class Db {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'tasbih.db');
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        target TEXT NOT NULL DEFAULT '',
        meaning TEXT NOT NULL DEFAULT '',
        goal INTEGER NOT NULL DEFAULT 0,
        beep_every INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0)''');
        await _createEntries(db, 'entries');
        await _createPrayers(db);
        await _seedZikirs(db);
        await _seedPrayers(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE categories ADD COLUMN target TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            "ALTER TABLE categories ADD COLUMN meaning TEXT NOT NULL DEFAULT ''",
          );
          await _addGoalColumns(db);
          await db.execute('UPDATE categories SET sort_order = 100 + id');
          await _createEntries(db, 'entries_new');
          await db.execute(
            "INSERT INTO entries_new SELECT category_id, date, '', count FROM entries",
          );
          await db.execute('DROP TABLE entries');
          await db.execute('ALTER TABLE entries_new RENAME TO entries');
          await _createPrayers(db);
          await _seedZikirs(db);
          await _seedPrayers(db);
        } else {
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE categories ADD COLUMN meaning TEXT NOT NULL DEFAULT ''",
            );
            // fill in meanings for zikirs that came from the default list
            for (final e in _defaultMeanings.entries) {
              await db.update(
                'categories',
                {'meaning': e.value},
                where: 'name = ?',
                whereArgs: [e.key],
              );
            }
          }
          if (oldVersion < 4) {
            await _addGoalColumns(db);
            // a plain number in the old suggested-count text becomes the goal
            await db.execute(
              "UPDATE categories SET goal = CAST(target AS INTEGER) "
              "WHERE target != '' AND target NOT GLOB '*[^0-9]*'",
            );
            for (final e in _defaultBeepEvery.entries) {
              await db.update(
                'categories',
                {'beep_every': e.value},
                where: 'name = ?',
                whereArgs: [e.key],
              );
            }
          }
        }
      },
    );
    return _db!;
  }

  static Future<void> _addGoalColumns(Database db) async {
    await db.execute(
      'ALTER TABLE categories ADD COLUMN goal INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE categories ADD COLUMN beep_every INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _createEntries(Database db, String table) =>
      db.execute('''CREATE TABLE $table(
        category_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        prayer TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL,
        PRIMARY KEY (category_id, date, prayer))''');

  static Future<void> _createPrayers(Database db) =>
      db.execute('''CREATE TABLE prayers(
        name TEXT PRIMARY KEY,
        ord INTEGER NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL)''');

  static Future<void> _seedZikirs(Database db) async {
    var i = 1;
    for (final z in _defaultZikirs) {
      await db.insert('categories', {
        'name': z.$1,
        'target': z.$2,
        'meaning': _defaultMeanings[z.$1] ?? '',
        'goal': int.tryParse(z.$2) ?? 0,
        'beep_every': _defaultBeepEvery[z.$1] ?? 0,
        'sort_order': i++,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedPrayers(Database db) async {
    var i = 0;
    for (final p in _defaultPrayers) {
      await db.insert('prayers', {
        'name': p.$1,
        'ord': i++,
        'start_min': p.$2,
        'end_min': p.$3,
      });
    }
  }

  // ---- categories ----

  /// Categories in queue order, each with its all-time total.
  static Future<List<Category>> categories() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.target, c.meaning, c.goal, c.beep_every, COALESCE(SUM(e.count), 0) AS total
      FROM categories c LEFT JOIN entries e ON e.category_id = c.id
      GROUP BY c.id ORDER BY c.sort_order, c.id''');
    return rows
        .map(
          (r) => Category(
            r['id'] as int,
            r['name'] as String,
            r['target'] as String,
            r['meaning'] as String,
            r['goal'] as int,
            r['beep_every'] as int,
            r['total'] as int,
          ),
        )
        .toList();
  }

  /// Returns the id of the new category, or of the existing one with the same name.
  static Future<int> addCategory(
    String name, {
    String target = '',
    String meaning = '',
    int goal = 0,
    int beepEvery = 0,
  }) async {
    final db = await _database;
    name = name.trim();
    final existing = await db.query(
      'categories',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    final m = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM categories',
    );
    return db.insert('categories', {
      'name': name,
      'target': target.trim(),
      'meaning': meaning.trim(),
      'goal': goal,
      'beep_every': beepEvery,
      'sort_order': m.first['n'],
    });
  }

  static Future<void> updateCategory(
    int id,
    String name,
    String target,
    String meaning,
    int goal,
    int beepEvery,
  ) async {
    final db = await _database;
    await db.update(
      'categories',
      {
        'name': name.trim(),
        'target': target.trim(),
        'meaning': meaning.trim(),
        'goal': goal,
        'beep_every': beepEvery,
      },
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> reorder(List<int> ids) async {
    final db = await _database;
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(
        'categories',
        {'sort_order': i + 1},
        where: 'id = ?',
        whereArgs: [ids[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> deleteCategory(int id) async {
    final db = await _database;
    await db.delete('entries', where: 'category_id = ?', whereArgs: [id]);
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ---- entries ----

  /// Adds [count] to the category's total for [date] and [prayer].
  static Future<void> saveCount(
    int categoryId,
    String date,
    String prayer,
    int count,
  ) async {
    final db = await _database;
    await db.rawInsert(
      '''
      INSERT INTO entries(category_id, date, prayer, count) VALUES(?, ?, ?, ?)
      ON CONFLICT(category_id, date, prayer) DO UPDATE SET count = count + excluded.count''',
      [categoryId, date, prayer, count],
    );
  }

  static Future<int> grandTotal() async {
    final db = await _database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(count), 0) AS t FROM entries',
    );
    return r.first['t'] as int;
  }

  /// Entries for a category, newest day first, limited to the last 6 months.
  static Future<List<DayEntry>> days(int categoryId) async {
    final db = await _database;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 5, 1);
    final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-01';
    final rows = await db.query(
      'entries',
      where: 'category_id = ? AND date >= ?',
      whereArgs: [categoryId, fromStr],
      orderBy: 'date DESC',
    );
    return rows
        .map(
          (r) => DayEntry(
            r['date'] as String,
            r['prayer'] as String,
            r['count'] as int,
          ),
        )
        .toList();
  }

  static Future<int> categoryTotal(int categoryId) async {
    final db = await _database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(count), 0) AS t FROM entries WHERE category_id = ?',
      [categoryId],
    );
    return r.first['t'] as int;
  }

  // ---- prayers ----

  static Future<List<Prayer>> prayers() async {
    final db = await _database;
    final rows = await db.query('prayers', orderBy: 'ord');
    return rows
        .map(
          (r) => Prayer(
            r['name'] as String,
            r['ord'] as int,
            r['start_min'] as int,
            r['end_min'] as int,
          ),
        )
        .toList();
  }

  static Future<void> updatePrayer(Prayer p) async {
    final db = await _database;
    await db.update(
      'prayers',
      {'start_min': p.startMin, 'end_min': p.endMin},
      where: 'name = ?',
      whereArgs: [p.name],
    );
  }
}
