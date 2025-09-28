import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/offline_models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'agent_x_offline.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Tasks table
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        server_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        priority TEXT NOT NULL,
        category TEXT NOT NULL,
        due_date TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        progress REAL NOT NULL DEFAULT 0.0,
        tags TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        conflict_data TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Events table
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        server_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        category TEXT NOT NULL,
        priority TEXT NOT NULL,
        location TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        conflict_data TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // News cache table
    await db.execute('''
      CREATE TABLE news_cache (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        summary TEXT,
        url TEXT NOT NULL,
        image_url TEXT,
        published_at TEXT NOT NULL,
        source TEXT NOT NULL,
        category TEXT NOT NULL,
        relevance_score REAL,
        tags TEXT,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');

    // Sync queue table
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');

    // User preferences cache
    await db.execute('''
      CREATE TABLE user_cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database migrations here
    if (oldVersion < newVersion) {
      // Add migration logic as needed
    }
  }

  // Clean up expired cache entries
  Future<void> cleanExpiredCache() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.delete(
      'news_cache',
      where: 'expires_at < ?',
      whereArgs: [now],
    );

    await db.delete(
      'user_cache',
      where: 'expires_at IS NOT NULL AND expires_at < ?',
      whereArgs: [now],
    );
  }
}
