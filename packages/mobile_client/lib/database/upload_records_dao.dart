import 'package:sqflite/sqflite.dart';

/// Data-access object for the `upload_records` table.
class UploadRecordsDao {
  final Database _db;

  UploadRecordsDao(this._db);

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  /// Bulk-inserts upload records inside a single transaction.
  ///
  /// Each map must contain the keys:
  ///   server_id, local_asset_id, file_name, album_name, file_size,
  ///   media_type, upload_status
  /// Optional keys: taken_at, uploaded_at
  Future<void> insertBatch(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final record in records) {
        await txn.insert(
          'upload_records',
          {
            ...record,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns all records with [upload_status] = 'completed' for [serverId].
  Future<List<Map<String, dynamic>>> getCompletedRecords(String serverId) async {
    return _db.query(
      'upload_records',
      where: 'server_id = ? AND upload_status = ?',
      whereArgs: [serverId, 'completed'],
      orderBy: 'uploaded_at DESC',
    );
  }

  /// Counts completed uploads for [serverId].
  Future<int> countCompleted(String serverId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM upload_records WHERE server_id = ? AND upload_status = ?',
      [serverId, 'completed'],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Sums [file_size] of completed uploads for [serverId].
  Future<int> sumCompletedSize(String serverId) async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(SUM(file_size), 0) AS total FROM upload_records WHERE server_id = ? AND upload_status = ?',
      [serverId, 'completed'],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  /// Updates [upload_status] (and optionally [uploaded_at]) for a record by [id].
  Future<void> updateStatus(int id, String status, {int? uploadedAt}) async {
    await _db.update(
      'upload_records',
      {
        'upload_status': status,
        if (uploadedAt != null) 'uploaded_at': uploadedAt,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes all completed records for the given [localAssetIds].
  Future<void> deleteByAssetIds(List<String> localAssetIds) async {
    if (localAssetIds.isEmpty) return;
    final placeholders = localAssetIds.map((_) => '?').join(',');
    await _db.rawDelete(
      'DELETE FROM upload_records WHERE local_asset_id IN ($placeholders)',
      localAssetIds,
    );
  }
}
