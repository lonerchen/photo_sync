import 'dart:io';

import 'package:common/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storage_server/services/i_server_database.dart';

import 'connected_devices_dao.dart';
import 'media_items_dao.dart';
import 'transfer_tasks_dao.dart';

/// Concrete SQLite implementation of [IServerDatabase] for the desktop server.
///
/// Uses sqflite_common_ffi for desktop (Windows / macOS / Linux) support.
class ServerDatabase implements IServerDatabase {
  static const _dbName = 'storage_server.db';
  static const _dbVersion = 1;

  Database? _db;

  late final ConnectedDevicesDao _devicesDao;
  late final MediaItemsDao _mediaItemsDao;
  late final TransferTasksDao _transferTasksDao;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Opens (or creates) the database. Must be called before any other method.
  Future<void> init({String? dbPath}) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final path = dbPath ?? await _defaultDbPath();
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );

    _devicesDao = ConnectedDevicesDao(_db!);
    _mediaItemsDao = MediaItemsDao(_db!);
    _transferTasksDao = TransferTasksDao(_db!);
  }

  Future<String> _defaultDbPath() async {
    final appSupport = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(appSupport.path, 'data'));
    await dataDir.create(recursive: true);
    return p.join(dataDir.path, _dbName);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE connected_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT UNIQUE NOT NULL,
        device_name TEXT NOT NULL,
        platform TEXT NOT NULL,
        storage_path TEXT NOT NULL,
        is_connected INTEGER NOT NULL DEFAULT 0,
        last_connected_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE media_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        taken_at INTEGER,
        thumbnail_path TEXT,
        thumbnail_status TEXT NOT NULL DEFAULT 'pending',
        live_photo_pair_name TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(device_id, album_name, file_name)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_media_device_album_taken
      ON media_items(device_id, album_name, taken_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE transfer_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        total_size INTEGER NOT NULL,
        uploaded_bytes INTEGER NOT NULL DEFAULT 0,
        temp_file_path TEXT NOT NULL,
        task_status TEXT NOT NULL,
        media_type TEXT NOT NULL,
        live_photo_pair_name TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Integrity check & rebuild (Task 6.5)
  // ---------------------------------------------------------------------------

  /// Runs `PRAGMA integrity_check`. Returns true if the database is healthy.
  Future<bool> checkIntegrity() async {
    _assertOpen();
    final result = await _db!.rawQuery('PRAGMA integrity_check');
    final status = result.first.values.first as String?;
    return status == 'ok';
  }

  /// Rebuilds the media_items table by scanning [storagePath].
  ///
  /// Directory layout expected:
  ///   `{storagePath}/{device_name}_{device_id}/{album_name}/*.ext`
  ///
  /// [onProgress] is called with (scannedFiles, estimatedTotal).
  Future<void> rebuildFromStorage(
    String storagePath, {
    void Function(int scanned, int estimated)? onProgress,
  }) async {
    _assertOpen();

    final root = Directory(storagePath);
    if (!root.existsSync()) return;

    // Collect all media files first for progress estimation.
    final allFiles = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && _isMediaFile(entity.path)) {
        allFiles.add(entity);
      }
    }

    final estimated = allFiles.length;
    int scanned = 0;

    for (final file in allFiles) {
      final parts = p.split(p.relative(file.path, from: storagePath));
      // Expected layout: {deviceId}/{album_name}/{file_name}
      // Legacy layout:   {device_name}_{device_id}/{album_name}/{file_name}
      if (parts.length < 3) continue;

      final deviceDir = parts[0];
      final albumName = parts[1];
      final fileName = parts[2];

      // Skip hidden/temp directories
      if (deviceDir.startsWith('.') || albumName.startsWith('.')) continue;

      // Try to parse deviceId: if contains underscore, treat as legacy
      // {device_name}_{device_id} format; otherwise use as-is.
      String deviceId;
      String deviceName;
      final lastUnderscore = deviceDir.lastIndexOf('_');
      if (lastUnderscore > 0) {
        deviceId = deviceDir.substring(lastUnderscore + 1);
        deviceName = deviceDir.substring(0, lastUnderscore);
      } else {
        deviceId = deviceDir;
        deviceName = deviceDir;
      }

      final stat = file.statSync();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Ensure device record exists.
      final existing = await _devicesDao.getDevice(deviceId);
      if (existing == null) {
        await _devicesDao.insertDevice(
          deviceId: deviceId,
          deviceName: deviceName,
          platform: 'unknown',
          storagePath: p.join(storagePath, deviceDir),
        );
      }

      // Upsert media_item with thumbnail_status reset to 'pending'.
      await _db!.execute('''
        INSERT INTO media_items
          (device_id, file_name, album_name, file_path, file_size, media_type,
           thumbnail_status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        ON CONFLICT(device_id, album_name, file_name) DO UPDATE SET
          file_path = excluded.file_path,
          file_size = excluded.file_size,
          thumbnail_status = 'pending',
          updated_at = excluded.updated_at
      ''', [
        deviceId,
        fileName,
        albumName,
        file.path,
        stat.size,
        _mediaTypeFromExtension(p.extension(fileName)),
        now,
        now,
      ]);

      scanned++;
      onProgress?.call(scanned, estimated);
    }
  }

  static bool _isMediaFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.jpg', '.jpeg', '.heic', '.png', '.gif', '.mov', '.mp4', '.m4v', '.webp'}
        .contains(ext);
  }

  static String _mediaTypeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.mov':
      case '.mp4':
      case '.m4v':
        return 'video';
      default:
        return 'image';
    }
  }

  void _assertOpen() {
    if (_db == null) throw StateError('ServerDatabase is not initialised. Call init() first.');
  }

  // ---------------------------------------------------------------------------
  // IServerDatabase – Storage migration
  // ---------------------------------------------------------------------------

  @override
  Future<int> migrateStoragePath({
    required String oldPath,
    required String newPath,
    void Function(int done, int total)? onProgress,
  }) async {
    _assertOpen();

    final oldRoot = _normalizeDirPath(oldPath);
    final newRoot = _normalizeDirPath(newPath);
    if (oldRoot == newRoot) {
      onProgress?.call(1, 1);
      return 0;
    }

    await Directory(newRoot).create(recursive: true);

    final tasks = <({String src, String dst})>[];
    final devices = await _devicesDao.getAllDevices();
    for (final d in devices) {
      final src = p.join(oldRoot, d.deviceId);
      if (await Directory(src).exists()) {
        tasks.add((src: src, dst: p.join(newRoot, d.deviceId)));
      }
    }

    final thumbSrc = p.join(oldRoot, '.thumbnails');
    if (await Directory(thumbSrc).exists()) {
      tasks.add((src: thumbSrc, dst: p.join(newRoot, '.thumbnails')));
    }

    final total = tasks.isEmpty ? 1 : tasks.length;
    int done = 0;
    onProgress?.call(done, total);

    for (final t in tasks) {
      await _moveDirectory(t.src, t.dst);
      done++;
      onProgress?.call(done, total);
    }

    await _db!.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE connected_devices
        SET storage_path = REPLACE(storage_path, ?, ?)
        WHERE storage_path LIKE ? || '%'
        ''',
        [oldRoot, newRoot, oldRoot],
      );

      await txn.rawUpdate(
        '''
        UPDATE media_items
        SET file_path = REPLACE(file_path, ?, ?),
            updated_at = ?
        WHERE file_path LIKE ? || '%'
        ''',
        [oldRoot, newRoot, DateTime.now().millisecondsSinceEpoch, oldRoot],
      );

      await txn.rawUpdate(
        '''
        UPDATE media_items
        SET thumbnail_path = REPLACE(thumbnail_path, ?, ?),
            updated_at = ?
        WHERE thumbnail_path IS NOT NULL
          AND thumbnail_path LIKE ? || '%'
        ''',
        [oldRoot, newRoot, DateTime.now().millisecondsSinceEpoch, oldRoot],
      );

      await txn.rawUpdate(
        '''
        UPDATE transfer_tasks
        SET temp_file_path = REPLACE(temp_file_path, ?, ?),
            updated_at = ?
        WHERE temp_file_path LIKE ? || '%'
        ''',
        [oldRoot, newRoot, DateTime.now().millisecondsSinceEpoch, oldRoot],
      );
    });

    onProgress?.call(total, total);
    return tasks.length;
  }

  String _normalizeDirPath(String rawPath) {
    var normalized = p.normalize(rawPath);
    while (normalized.endsWith(Platform.pathSeparator) &&
        normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<void> _moveDirectory(String sourcePath, String targetPath) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) return;

    final target = Directory(targetPath);
    await target.parent.create(recursive: true);

    try {
      await source.rename(targetPath);
      return;
    } catch (_) {
      // Cross-volume move fallback: copy + delete source.
    }

    await _copyDirectory(source, target);
    await source.delete(recursive: true);
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory(p.join(target.path, p.basename(entity.path))),
        );
      } else if (entity is File) {
        final dst = File(p.join(target.path, p.basename(entity.path)));
        await dst.parent.create(recursive: true);
        await entity.copy(dst.path);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IServerDatabase – Devices
  // ---------------------------------------------------------------------------

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String storagePath,
  }) {
    _assertOpen();
    return _devicesDao.registerDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      storagePath: storagePath,
    );
  }

  @override
  Future<List<DeviceInfo>> getAllDevices() {
    _assertOpen();
    return _devicesDao.getAllDevices();
  }

  @override
  Future<DeviceInfo?> getDevice(String deviceId) {
    _assertOpen();
    return _devicesDao.getDevice(deviceId);
  }

  @override
  Future<void> setDeviceConnected(String deviceId, {required bool connected}) {
    _assertOpen();
    return _devicesDao.setDeviceConnected(deviceId, connected: connected);
  }

  // ---------------------------------------------------------------------------
  // IServerDatabase – Albums
  // ---------------------------------------------------------------------------

  @override
  Future<List<Album>> getAlbums(String deviceId) {
    _assertOpen();
    return _mediaItemsDao.getAlbums(deviceId);
  }

  // ---------------------------------------------------------------------------
  // IServerDatabase – Media items
  // ---------------------------------------------------------------------------

  @override
  Future<({int total, List<MediaItem> items})> getMediaItems({
    required String deviceId,
    required String albumName,
    required int page,
    required int pageSize,
    int? startDate,
    int? endDate,
    String sortOrder = 'desc',
  }) {
    _assertOpen();
    return _mediaItemsDao.getMediaItems(
      deviceId: deviceId,
      albumName: albumName,
      page: page,
      pageSize: pageSize,
      startDate: startDate,
      endDate: endDate,
      sortOrder: sortOrder,
    );
  }

  @override
  Future<MediaItem?> getMediaItem(int mediaId) {
    _assertOpen();
    return _mediaItemsDao.getMediaItem(mediaId);
  }

  @override
  Future<List<String>> getExistingFileNames({
    required String deviceId,
    required String albumName,
    required List<String> fileNames,
  }) {
    _assertOpen();
    return _mediaItemsDao.getExistingFileNames(
      deviceId: deviceId,
      albumName: albumName,
      fileNames: fileNames,
    );
  }

  @override
  Future<MediaItem> insertMediaItem({
    required String deviceId,
    required String fileName,
    required String albumName,
    required String filePath,
    required int fileSize,
    required MediaType mediaType,
    int? takenAt,
    String? livePhotoPairName,
  }) {
    _assertOpen();
    return _mediaItemsDao.insertMediaItem(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
      filePath: filePath,
      fileSize: fileSize,
      mediaType: mediaType,
      takenAt: takenAt,
      livePhotoPairName: livePhotoPairName,
    );
  }

  @override
  Future<void> updateThumbnail({
    required int mediaId,
    required String thumbnailPath,
    required String thumbnailStatus,
  }) {
    _assertOpen();
    return _mediaItemsDao.updateThumbnail(
      mediaId: mediaId,
      thumbnailPath: thumbnailPath,
      thumbnailStatus: thumbnailStatus,
    );
  }

  @override
  Future<List<int>> getPendingThumbnailIds() async {
    _assertOpen();
    final rows = await _db!.query(
      'media_items',
      columns: ['id'],
      where: "thumbnail_status = 'pending'",
    );
    return rows.map((r) => r['id'] as int).toList();
  }

  // ---------------------------------------------------------------------------
  // IServerDatabase – Transfer tasks
  // ---------------------------------------------------------------------------

  @override
  Future<int> getUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) {
    _assertOpen();
    return _transferTasksDao.getUploadedBytes(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
    );
  }

  @override
  Future<({MediaType mediaType, String? livePhotoPairName})?> getTransferTaskMeta({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) {
    _assertOpen();
    return _transferTasksDao.getTransferTaskMeta(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
    );
  }

  @override
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
  }) {
    _assertOpen();
    return _transferTasksDao.upsertTransferTask(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
      totalSize: totalSize,
      uploadedBytes: uploadedBytes,
      tempFilePath: tempFilePath,
      taskStatus: taskStatus,
      mediaType: mediaType,
      livePhotoPairName: livePhotoPairName,
    );
  }

  @override
  Future<void> updateUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
    required int uploadedBytes,
  }) {
    _assertOpen();
    return _transferTasksDao.updateUploadedBytes(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
      uploadedBytes: uploadedBytes,
    );
  }

  @override
  Future<void> completeTransferTask({
    required String deviceId,
    required String fileName,
    required String albumName,
  }) {
    _assertOpen();
    return _transferTasksDao.completeTransferTask(
      deviceId: deviceId,
      fileName: fileName,
      albumName: albumName,
    );
  }
}
