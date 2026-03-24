import 'package:common/common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Data-access object for the `transfer_tasks` table.
class TransferTasksDao {
  final Database _db;

  TransferTasksDao(this._db);

  // ---------------------------------------------------------------------------
  // Upsert
  // ---------------------------------------------------------------------------

  /// Creates or updates a transfer task record.
  Future<void> upsertTransferTask({
    required String deviceId,
    required String fileName,
    required String albumName,
    required int totalSize,
    required int uploadedBytes,
    required String tempFilePath,
    required String taskStatus,
    required MediaType mediaType,
    String? livePhotoPairName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if an active (non-terminal) task already exists.
    final existing = await _db.query(
      'transfer_tasks',
      columns: ['id'],
      where: 'device_id = ? AND file_name = ? AND album_name = ?'
          " AND task_status NOT IN ('completed', 'failed')",
      whereArgs: [deviceId, fileName, albumName],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await _db.update(
        'transfer_tasks',
        {
          'total_size': totalSize,
          'uploaded_bytes': uploadedBytes,
          'temp_file_path': tempFilePath,
          'task_status': taskStatus,
          'media_type': mediaType.toJson(),
          'live_photo_pair_name': livePhotoPairName,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      // 清理同名的旧 completed/failed 记录，避免 getUploadedBytes 读到过期数据
      await _db.delete(
        'transfer_tasks',
        where: 'device_id = ? AND file_name = ? AND album_name = ?'
            " AND task_status IN ('completed', 'failed')",
        whereArgs: [deviceId, fileName, albumName],
      );
      await _db.insert('transfer_tasks', {
        'device_id': deviceId,
        'file_name': fileName,
        'album_name': albumName,
        'total_size': totalSize,
        'uploaded_bytes': uploadedBytes,
        'temp_file_path': tempFilePath,
        'task_status': taskStatus,
        'media_type': mediaType.toJson(),
        'live_photo_pair_name': livePhotoPairName,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the number of already-uploaded bytes, or 0 if no active task exists.
  Future<int> getUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) async {
    final rows = await _db.query(
      'transfer_tasks',
      columns: ['uploaded_bytes'],
      where: 'device_id = ? AND file_name = ? AND album_name = ?'
          " AND task_status NOT IN ('completed', 'failed')",
      whereArgs: [deviceId, fileName, albumName],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['uploaded_bytes'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  Future<void> updateUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
    required int uploadedBytes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_tasks',
      {'uploaded_bytes': uploadedBytes, 'updated_at': now},
      where: 'device_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [deviceId, fileName, albumName],
    );
  }

  Future<void> completeTransferTask({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_tasks',
      {'task_status': 'completed', 'updated_at': now},
      where: 'device_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [deviceId, fileName, albumName],
    );
  }

  Future<void> failTransferTask({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_tasks',
      {'task_status': 'failed', 'updated_at': now},
      where: 'device_id = ? AND file_name = ? AND album_name = ?',
      whereArgs: [deviceId, fileName, albumName],
    );
  }
}
