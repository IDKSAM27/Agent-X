import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'agent_x.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Upgrade News Table
      await db.execute('DROP TABLE IF EXISTS news');
      await db.execute('''
        CREATE TABLE news(
          id TEXT PRIMARY KEY,
          title TEXT,
          description TEXT,
          summary TEXT,
          url TEXT,
          source TEXT,
          published_at TEXT,
          category TEXT,
          image_url TEXT,
          relevance_score REAL,
          quality_score REAL,
          tags TEXT,
          keywords TEXT,
          is_local_event INTEGER,
          is_urgent INTEGER,
          event_date TEXT,
          event_location TEXT,
          available_actions TEXT,
          cached_at TEXT
        )
      ''');
    }
    
    if (oldVersion < 3) {
      // Add priority column to events table
      // Check if column exists first to be safe (though version check should suffice)
      try {
        await db.execute('ALTER TABLE events ADD COLUMN priority TEXT DEFAULT "medium"');
      } catch (e) {
        print("Column priority might already exist: $e");
      }
    }
  }


  Future<void> _onCreate(Database db, int version) async {
    // Tasks Table
    await db.execute('''
      CREATE TABLE tasks(
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        priority TEXT,
        category TEXT,
        due_date TEXT,
        is_completed INTEGER,
        progress REAL,
        tags TEXT,
        is_synced INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0,
        last_updated TEXT
      )
    ''');

    // Events Table
    await db.execute('''
      CREATE TABLE events(
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        start_time TEXT,
        end_time TEXT,
        category TEXT,
        priority TEXT,
        is_all_day INTEGER,
        is_synced INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0,
        last_updated TEXT
      )
    ''');

    // News Table
    await db.execute('''
      CREATE TABLE news(
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        summary TEXT,
        url TEXT,
        source TEXT,
        published_at TEXT,
        category TEXT,
        image_url TEXT,
        relevance_score REAL,
        quality_score REAL,
        tags TEXT,
        keywords TEXT,
        is_local_event INTEGER,
        is_urgent INTEGER,
        event_date TEXT,
        event_location TEXT,
        available_actions TEXT,
        cached_at TEXT
      )
    ''');

    // Chat Sessions Table
    await db.execute('''
      CREATE TABLE chat_sessions(
        id INTEGER PRIMARY KEY,
        title TEXT,
        created_at TEXT,
        updated_at TEXT,
        profession TEXT
      )
    ''');

    // Chat Messages Table
    await db.execute('''
      CREATE TABLE chat_messages(
        id TEXT PRIMARY KEY,
        session_id INTEGER,
        content TEXT,
        type TEXT,
        timestamp TEXT,
        is_synced INTEGER DEFAULT 1,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    // Sync Queue Table
    await db.execute('''
      CREATE TABLE sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT, -- 'task', 'event', 'message'
        operation TEXT, -- 'create', 'update', 'delete'
        entity_id TEXT,
        payload TEXT,
        created_at TEXT
      )
    ''');
  }

  // --- Generic CRUD Helpers ---

  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAllRows(String table) async {
    final db = await database;
    return await db.query(table);
  }

  Future<int> update(String table, Map<String, dynamic> row, String columnId) async {
    final db = await database;
    String id = row[columnId];
    
    // Ensure we update metadata
    final Map<String, dynamic> data = Map.from(row);
    if (!data.containsKey('last_updated')) {
      data['last_updated'] = DateTime.now().toIso8601String();
    }
    // If we are updating locally, we usually want to mark as unsynced (0)
    // But sometimes we might be updating FROM sync (is_synced=1)
    // So we respect the passed value if present, otherwise default to 0 (unsynced)
    if (!data.containsKey('is_synced')) {
      data['is_synced'] = 0;
    }

    return await db.update(table, data, where: '$columnId = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, String id) async {
    final db = await database;
    // Instead of hard delete, we might want soft delete for sync
    // But for now, let's stick to the plan:
    // If it's unsynced and we delete it, we just remove it.
    // If it's synced, we need to mark it as deleted so we can sync the deletion.
    // However, the current schema has is_deleted.
    
    // Check if item is synced
    final List<Map<String, dynamic>> result = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      final item = result.first;
      if (item['is_synced'] == 1) {
        // Soft delete
        return await db.update(table, {
          'is_deleted': 1,
          'is_synced': 0,
          'last_updated': DateTime.now().toIso8601String()
        }, where: 'id = ?', whereArgs: [id]);
      }
    }
    
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
  
  // --- Specific Queries ---
  
  Future<void> updateEntityId(String table, String oldId, String newId) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Update the entity itself
      await txn.update(table, {'id': newId, 'is_synced': 1}, where: 'id = ?', whereArgs: [oldId]);
      
      // 2. Update any pending sync queue items that reference this ID
      // We only update items that were created AFTER the creation event (which should be rare if we process sequentially)
      // But more importantly, if we have queued updates for this item, they need to point to the new ID.
      await txn.update('sync_queue', {'entity_id': newId}, where: 'entity_id = ?', whereArgs: [oldId]);
    });
  }
  
  Future<List<Map<String, dynamic>>> getUnsyncedItems(String table) async {
    final db = await database;
    // Get items that are not synced AND not deleted (unless we want to sync deletions separately)
    // Actually, sync queue handles the operations. This helper might be for initial load or recovery.
    return await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
  }
  
  Future<void> markAsSynced(String table, String id) async {
    final db = await database;
    await db.update(table, {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToSyncQueue(String entityType, String operation, String entityId, String payload) async {
    final db = await database;
    await db.insert('sync_queue', {
      'entity_type': entityType,
      'operation': operation,
      'entity_id': entityId,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await database;
    return await db.query('sync_queue', orderBy: 'created_at ASC');
  }

  Future<void> removeFromSyncQueue(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSyncedSessionMessages(int sessionId) async {
    final db = await database;
    await db.delete('chat_messages', where: 'session_id = ? AND is_synced = 1', whereArgs: [sessionId]);
  }
}
