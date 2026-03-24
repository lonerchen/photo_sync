import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'connected_servers_dao.dart';
import 'transfer_tasks_dao.dart';
import 'upload_records_dao.dart';

/// Singleton SQLite database for the mobile client.
///
/// Manages the three tables:
///   - `connected_servers`
///   - `upload_records`
///   - `transfer_tasks`
class MobileDatabase {
  static const _dbName = 'mobile_client.db';
  static const _dbVersion = 2;

  static final MobileDatabase _instance = MobileDatabase._();
  MobileDatabase._();
  factory MobileDatabase() => _instance;

  Database? _db;

  late final ConnectedServersDao connectedServersDao;
  late final UploadRecordsDao uploadRecordsDao;
  late final TransferTasksDao transferTasksDao;

  /// Opens (or creates) the database. Must be called before any DAO access.
  Future<void> init() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_dbName';

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    connectedServersDao = ConnectedServersDao(_db!);
    uploadRecordsDao = UploadRecordsDao(_db!);
    transferTasksDao = TransferTasksDao(_db!);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE connected_servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT UNIQUE NOT NULL,
        server_name TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        port INTEGER NOT NULL,
        last_connected_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE upload_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL,
        local_asset_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        taken_at INTEGER,
        upload_status TEXT NOT NULL,
        uploaded_at INTEGER,
        created_at INTEGER NOT NULL,
        UNIQUE(server_id, local_asset_id, file_name)
      )
    ''');

    await db.execute('''
      CREATE TABLE transfer_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        local_asset_id TEXT NOT NULL,
        total_size INTEGER NOT NULL,
        uploaded_bytes INTEGER NOT NULL DEFAULT 0,
        chunk_size INTEGER NOT NULL,
        task_status TEXT NOT NULL,
        media_type TEXT NOT NULL,
        live_photo_pair_name TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Database get db {
    if (_db == null) throw StateError('MobileDatabase not initialised. Call init() first.');
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add UNIQUE constraint by recreating the table (SQLite doesn't support ADD CONSTRAINT).
      // First deduplicate: keep only the latest row per (server_id, local_asset_id, file_name).
      await db.execute('''
        DELETE FROM upload_records WHERE id NOT IN (
          SELECT MAX(id) FROM upload_records GROUP BY server_id, local_asset_id, file_name
        )
      ''');
      // Recreate with UNIQUE constraint.
      await db.execute('ALTER TABLE upload_records RENAME TO upload_records_old');
      await db.execute('''
        CREATE TABLE upload_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id TEXT NOT NULL,
          local_asset_id TEXT NOT NULL,
          file_name TEXT NOT NULL,
          album_name TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          media_type TEXT NOT NULL,
          taken_at INTEGER,
          upload_status TEXT NOT NULL,
          uploaded_at INTEGER,
          created_at INTEGER NOT NULL,
          UNIQUE(server_id, local_asset_id, file_name)
        )
      ''');
      await db.execute('''
        INSERT INTO upload_records SELECT * FROM upload_records_old
      ''');
      await db.execute('DROP TABLE upload_records_old');
    }
  }
}
