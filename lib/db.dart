import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Category {
  final int id;
  final String name;
  final int total;
  Category(this.id, this.name, this.total);
}

class DayCount {
  final String date; // yyyy-MM-dd
  final int count;
  DayCount(this.date, this.count);
}

class Db {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'tasbih.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
      await db.execute('''CREATE TABLE entries(
        category_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        count INTEGER NOT NULL,
        PRIMARY KEY (category_id, date))''');
    });
    return _db!;
  }

  static Future<List<Category>> categories() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, COALESCE(SUM(e.count), 0) AS total
      FROM categories c LEFT JOIN entries e ON e.category_id = c.id
      GROUP BY c.id ORDER BY c.name''');
    return rows
        .map((r) => Category(r['id'] as int, r['name'] as String, r['total'] as int))
        .toList();
  }

  static Future<int> addCategory(String name) async {
    final db = await _database;
    return db.insert('categories', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> deleteCategory(int id) async {
    final db = await _database;
    await db.delete('entries', where: 'category_id = ?', whereArgs: [id]);
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  /// Adds [count] to the category's total for [date] (same-day saves accumulate).
  static Future<void> saveCount(int categoryId, String date, int count) async {
    final db = await _database;
    await db.rawInsert('''
      INSERT INTO entries(category_id, date, count) VALUES(?, ?, ?)
      ON CONFLICT(category_id, date) DO UPDATE SET count = count + excluded.count''',
        [categoryId, date, count]);
  }

  static Future<int> grandTotal() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COALESCE(SUM(count), 0) AS t FROM entries');
    return r.first['t'] as int;
  }

  /// Daily rows for a category, newest first, limited to the last 6 months.
  static Future<List<DayCount>> days(int categoryId) async {
    final db = await _database;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 5, 1);
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-01';
    final rows = await db.query('entries',
        where: 'category_id = ? AND date >= ?',
        whereArgs: [categoryId, fromStr],
        orderBy: 'date DESC');
    return rows.map((r) => DayCount(r['date'] as String, r['count'] as int)).toList();
  }

  static Future<int> categoryTotal(int categoryId) async {
    final db = await _database;
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(count), 0) AS t FROM entries WHERE category_id = ?',
        [categoryId]);
    return r.first['t'] as int;
  }
}
