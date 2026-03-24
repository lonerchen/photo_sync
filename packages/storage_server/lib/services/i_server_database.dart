import 'package:common/common.dart';

/// Database interface used by the HTTP/WebSocket server.
///
/// Concrete implementation lives in the database layer (task 6).
abstract interface class IServerDatabase {
  // -------------------------------------------------------------------------
  // Devices
  // -------------------------------------------------------------------------

  /// Register or update a device. Returns the stored [DeviceInfo].
  Future<DeviceInfo> registerDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String storagePath,
  });

  /// Returns all known devices.
  Future<List<DeviceInfo>> getAllDevices();

  /// Returns the device with [deviceId], or null if not found.
  Future<DeviceInfo?> getDevice(String deviceId);

  /// Updates the `is_connected` flag for [deviceId].
  Future<void> setDeviceConnected(String deviceId, {required bool connected});

  // -------------------------------------------------------------------------
  // Albums
  // -------------------------------------------------------------------------

  /// Returns all albums for [deviceId].
  Future<List<Album>> getAlbums(String deviceId);

  // -------------------------------------------------------------------------
  // Media items
  // -------------------------------------------------------------------------

  /// Returns a paginated list of media items for [deviceId] / [albumName].
  ///
  /// [startDate] and [endDate] are optional Unix-ms timestamps.
  /// [sortOrder] is either 'desc' (default, newest first) or 'asc'.
  Future<({int total, List<MediaItem> items})> getMediaItems({
    required String deviceId,
    required String albumName,
    required int page,
    required int pageSize,
    int? startDate,
    int? endDate,
    String sortOrder,
  });

  /// Returns the [MediaItem] with [mediaId], or null if not found.
  Future<MediaItem?> getMediaItem(int mediaId);

  /// Checks which of [fileNames] already exist in [albumName] for [deviceId].
  Future<List<String>> getExistingFileNames({
    required String deviceId,
    required String albumName,
    required List<String> fileNames,
  });

  /// Inserts a new media item record. Returns the inserted [MediaItem].
  Future<MediaItem> insertMediaItem({
    required String deviceId,
    required String fileName,
    required String albumName,
    required String filePath,
    required int fileSize,
    required MediaType mediaType,
    int? takenAt,
    String? livePhotoPairName,
  });

  /// Updates the thumbnail path and status for [mediaId].
  Future<void> updateThumbnail({
    required int mediaId,
    required String thumbnailPath,
    required String thumbnailStatus,
  });

  /// Returns IDs of all media items with thumbnail_status = 'pending'.
  Future<List<int>> getPendingThumbnailIds();

  // -------------------------------------------------------------------------
  // Transfer tasks
  // -------------------------------------------------------------------------

  /// Returns the number of already-uploaded bytes for a transfer task,
  /// or 0 if no task exists yet.
  Future<int> getUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
  });

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
  });

  /// Updates the uploaded bytes for an in-progress transfer task.
  Future<void> updateUploadedBytes({
    required String deviceId,
    required String fileName,
    required String albumName,
    required int uploadedBytes,
  });

  /// Marks a transfer task as completed.
  Future<void> completeTransferTask({
    required String deviceId,
    required String fileName,
    required String albumName,
  });
}
