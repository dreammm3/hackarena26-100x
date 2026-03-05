import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class UsageDatabase {
  static final UsageDatabase instance = UsageDatabase._init();
  static Database? _database;

  UsageDatabase._init();

  Future<Database> get database async {
    if (kIsWeb) throw UnsupportedError("SQLite not supported on Web");
    if (_database != null) return _database!;
    _database = await _initDB('usage_stats.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usage_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL,
        merchant_name TEXT NOT NULL,
        date TEXT NOT NULL,
        minutes_used INTEGER NOT NULL,
        UNIQUE(package_name, date)
      )
    ''');
  }

  Future<void> insertUsage(String packageName, String merchantName, String date, int minutes) async {
    final db = await instance.database;
    await db.insert(
      'usage_stats',
      {
        'package_name': packageName,
        'merchant_name': merchantName,
        'date': date,
        'minutes_used': minutes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUsageForDate(String date) async {
    if (kIsWeb) return [];
    final db = await instance.database;
    return await db.query('usage_stats', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getAllUsage() async {
    if (kIsWeb) return [];
    final db = await instance.database;
    return await db.query('usage_stats', orderBy: 'date DESC');
  }
}
