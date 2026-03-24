import 'package:sqflite/sqflite.dart';

/// Data-access object for the `transfer_tasks` table (mobile client side).
class TransferTasksDao {
  final Database _db;

  TransferTasksDao(this._db);

  // ---------------------------------------------------------------------------
  // Upsert
  // ---------------------------------------------------------------------------

  /// Inserts or updates a transfer task identified by (server_id, file_name, album_name).
  ///
  /// Required keys: server_id, file_name, album_name, local_asset_id,
  ///   total_size, chunk_size, task_status, media_type
  /// Optional keys: uploaded_bytes, live_photo_pair_name
  Future<void> upsertTask(Map<String, dynamic> task) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      'transfer_tasks',
      columns: ['id'],
      where: 'server_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [task['server_id'], task['file_name'], task['album_name']],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await _db.update(
        'transfer_tasks',
        {
          ...task,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await _db.insert('transfer_tasks', {
        ...task,
        'uploaded_bytes': task['uploaded_bytes'] ?? 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the task for the given (server_id, file_name, album_name), or null.
  Future<Map<String, dynamic>?> getTask(
    String serverId,
    String fileName,
    String albumName,
  ) async {
    final rows = await _db.query(
      'transfer_tasks',
      where: 'server_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [serverId, fileName, albumName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Returns all non-completed tasks for [serverId] (pending/uploading/paused/failed).
  Future<List<Map<String, dynamic>>> getPendingTasks(String serverId) async {
    return _db.query(
      'transfer_tasks',
      where: "server_id = ? AND task_status NOT IN ('completed')",
      whereArgs: [serverId],
      orderBy: 'created_at ASC',
    );
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  /// Updates [uploaded_bytes] and [updated_at] for the matching task.
  Future<void> updateUploadedBytes(
    String serverId,
    String fileName,
    String albumName,
    int uploadedBytes,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_tasks',
      {'uploaded_bytes': uploadedBytes, 'updated_at': now},
      where: 'server_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [serverId, fileName, albumName],
    );
  }

  /// Marks the task as completed.
  Future<void> completeTask(
    String serverId,
    String fileName,
    String albumName,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_tasks',
      {'task_status': 'completed', 'updated_at': now},
      where: 'server_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [serverId, fileName, albumName],
    );
  }
}
