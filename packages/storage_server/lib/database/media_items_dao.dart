import 'package:common/common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Data-access object for the `media_items` table.
class MediaItemsDao {
  final Database _db;

  MediaItemsDao(this._db);

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  Future<MediaItem> insertMediaItem({
    required String deviceId,
    required String fileName,
    required String albumName,
    required String filePath,
    required int fileSize,
    required MediaType mediaType,
    int? takenAt,
    String? livePhotoPairName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.insert('media_items', {
      'device_id': deviceId,
      'file_name': fileName,
      'album_name': albumName,
      'file_path': filePath,
      'file_size': fileSize,
      'media_type': mediaType.toJson(),
      if (takenAt != null) 'taken_at': takenAt,
      'thumbnail_status': 'pending',
      if (livePhotoPairName != null) 'live_photo_pair_name': livePhotoPairName,
      'created_at': now,
      'updated_at': now,
    });
    return (await getMediaItem(id))!;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Future<MediaItem?> getMediaItem(int id) async {
    final rows = await _db.query(
      'media_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToMediaItem(rows.first);
  }

  /// Paginated query with optional time-range filter.
  Future<({int total, List<MediaItem> items})> getMediaItems({
    required String deviceId,
    required String albumName,
    required int page,
    required int pageSize,
    int? startDate,
    int? endDate,
  }) async {
    final where = StringBuffer('device_id = ? AND album_name = ?');
    final args = <dynamic>[deviceId, albumName];

    if (startDate != null) {
      where.write(' AND taken_at >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      where.write(' AND taken_at <= ?');
      args.add(endDate);
    }

    final whereStr = where.toString();

    // Count total matching rows.
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM media_items WHERE $whereStr',
      args,
    );
    final total = (countResult.first['cnt'] as int?) ?? 0;

    // Fetch page.
    final offset = (page - 1) * pageSize;
    final rows = await _db.query(
      'media_items',
      where: whereStr,
      whereArgs: args,
      orderBy: 'taken_at DESC',
      limit: pageSize,
      offset: offset,
    );

    return (total: total, items: rows.map(_rowToMediaItem).toList());
  }

  /// Returns album summaries for [deviceId].
  Future<List<Album>> getAlbums(String deviceId) async {
    final rows = await _db.rawQuery('''
      SELECT album_name,
             COUNT(*) AS media_count,
             (SELECT thumbnail_path
              FROM media_items mi2
              WHERE mi2.device_id = mi.device_id
                AND mi2.album_name = mi.album_name
                AND mi2.thumbnail_status = 'ready'
              ORDER BY taken_at DESC
              LIMIT 1) AS cover_thumbnail_path
      FROM media_items mi
      WHERE device_id = ?
      GROUP BY album_name
      ORDER BY album_name
    ''', [deviceId]);

    return rows
        .map((r) => Album(
              albumName: r['album_name'] as String,
              deviceId: deviceId,
              mediaCount: r['media_count'] as int,
              coverThumbnailUrl: r['cover_thumbnail_path'] as String?,
            ))
        .toList();
  }

  /// Returns which of [fileNames] already exist for [deviceId] / [albumName].
  Future<List<String>> getExistingFileNames({
    required String deviceId,
    required String albumName,
    required List<String> fileNames,
  }) async {
    if (fileNames.isEmpty) return [];

    final placeholders = List.filled(fileNames.length, '?').join(', ');
    final rows = await _db.rawQuery(
      '''
      SELECT file_name FROM media_items
      WHERE device_id = ? AND album_name = ?
        AND file_name IN ($placeholders)
      ''',
      [deviceId, albumName, ...fileNames],
    );
    return rows.map((r) => r['file_name'] as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  Future<void> updateThumbnail({
    required int mediaId,
    required String thumbnailPath,
    required String thumbnailStatus,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'media_items',
      {
        'thumbnail_path': thumbnailPath,
        'thumbnail_status': thumbnailStatus,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  Future<void> updateThumbnailStatus({
    required int mediaId,
    required String thumbnailStatus,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'media_items',
      {'thumbnail_status': thumbnailStatus, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static MediaItem _rowToMediaItem(Map<String, dynamic> row) => MediaItem(
        id: row['id'] as int,
        deviceId: row['device_id'] as String,
        fileName: row['file_name'] as String,
        albumName: row['album_name'] as String,
        filePath: row['file_path'] as String,
        fileSize: row['file_size'] as int,
        mediaType: MediaType.fromJson(row['media_type'] as String),
        takenAt: row['taken_at'] as int?,
        thumbnailPath: row['thumbnail_path'] as String?,
        thumbnailStatus: ThumbnailStatus.fromJson(
          row['thumbnail_status'] as String? ?? 'pending',
        ),
        livePhotoPairName: row['live_photo_pair_name'] as String?,
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
      );
}
