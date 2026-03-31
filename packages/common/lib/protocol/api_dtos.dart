import '../models/models.dart';

// ---------------------------------------------------------------------------
// Unified API response wrapper
// ---------------------------------------------------------------------------

/// Unified HTTP API response envelope.
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  const ApiResponse({
    required this.code,
    required this.message,
    this.data,
  });

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromData,
  ) =>
      ApiResponse(
        code: json['code'] as int,
        message: json['message'] as String,
        data: json['data'] != null && fromData != null
            ? fromData(json['data'])
            : null,
      );

  Map<String, dynamic> toJson([dynamic Function(T)? toData]) => {
        'code': code,
        'message': message,
        if (data != null && toData != null) 'data': toData(data as T),
      };
}

// ---------------------------------------------------------------------------
// Upload DTOs
// ---------------------------------------------------------------------------

/// Request body for POST /upload/init.
class UploadInitRequest {
  final String deviceId;
  final String fileName;
  final String albumName;
  final int totalSize;
  final MediaType mediaType;
  final String? livePhotoPairName;
  final int? takenAt;

  const UploadInitRequest({
    required this.deviceId,
    required this.fileName,
    required this.albumName,
    required this.totalSize,
    required this.mediaType,
    this.livePhotoPairName,
    this.takenAt,
  });

  factory UploadInitRequest.fromJson(Map<String, dynamic> json) =>
      UploadInitRequest(
        deviceId: json['device_id'] as String,
        fileName: json['file_name'] as String,
        albumName: json['album_name'] as String,
        totalSize: json['total_size'] as int,
        mediaType: MediaType.fromJson(json['media_type'] as String),
        livePhotoPairName: json['live_photo_pair_name'] as String?,
        takenAt: json['taken_at'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'file_name': fileName,
        'album_name': albumName,
        'total_size': totalSize,
        'media_type': mediaType.toJson(),
        if (livePhotoPairName != null) 'live_photo_pair_name': livePhotoPairName,
        if (takenAt != null) 'taken_at': takenAt,
      };
}

/// Response data for POST /upload/init.
class UploadInitResponse {
  final int uploadedBytes;
  final int chunkSize;

  const UploadInitResponse({
    required this.uploadedBytes,
    required this.chunkSize,
  });

  factory UploadInitResponse.fromJson(Map<String, dynamic> json) =>
      UploadInitResponse(
        uploadedBytes: json['uploaded_bytes'] as int,
        chunkSize: json['chunk_size'] as int,
      );

  Map<String, dynamic> toJson() => {
        'uploaded_bytes': uploadedBytes,
        'chunk_size': chunkSize,
      };
}

/// Multipart form fields for POST /upload/chunk.
class UploadChunkRequest {
  final String deviceId;
  final String fileName;
  final String albumName;
  final int offset;

  const UploadChunkRequest({
    required this.deviceId,
    required this.fileName,
    required this.albumName,
    required this.offset,
  });

  factory UploadChunkRequest.fromJson(Map<String, dynamic> json) =>
      UploadChunkRequest(
        deviceId: json['device_id'] as String,
        fileName: json['file_name'] as String,
        albumName: json['album_name'] as String,
        offset: json['offset'] as int,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'file_name': fileName,
        'album_name': albumName,
        'offset': offset,
      };
}

/// Request body for POST /upload/complete.
class UploadCompleteRequest {
  final String deviceId;
  final String fileName;
  final String albumName;
  final int totalSize;
  final String? thumbnailBase64;

  const UploadCompleteRequest({
    required this.deviceId,
    required this.fileName,
    required this.albumName,
    required this.totalSize,
    this.thumbnailBase64,
  });

  factory UploadCompleteRequest.fromJson(Map<String, dynamic> json) =>
      UploadCompleteRequest(
        deviceId: json['device_id'] as String,
        fileName: json['file_name'] as String,
        albumName: json['album_name'] as String,
        totalSize: json['total_size'] as int,
        thumbnailBase64: json['thumbnail_base64'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'file_name': fileName,
        'album_name': albumName,
        'total_size': totalSize,
        if (thumbnailBase64 != null) 'thumbnail_base64': thumbnailBase64,
      };
}

// ---------------------------------------------------------------------------
// Deduplication DTOs
// ---------------------------------------------------------------------------

/// Request body for POST /upload/check-exists.
class CheckExistsRequest {
  final String deviceId;
  final String albumName;
  final List<String> fileNames;

  const CheckExistsRequest({
    required this.deviceId,
    required this.albumName,
    required this.fileNames,
  });

  factory CheckExistsRequest.fromJson(Map<String, dynamic> json) =>
      CheckExistsRequest(
        deviceId: json['device_id'] as String,
        albumName: json['album_name'] as String,
        fileNames: List<String>.from(json['file_names'] as List),
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'album_name': albumName,
        'file_names': fileNames,
      };
}

/// Response data for POST /upload/check-exists.
class CheckExistsResponse {
  final List<String> exists;
  final List<String> notExists;

  const CheckExistsResponse({
    required this.exists,
    required this.notExists,
  });

  factory CheckExistsResponse.fromJson(Map<String, dynamic> json) =>
      CheckExistsResponse(
        exists: List<String>.from(json['exists'] as List),
        notExists: List<String>.from(json['not_exists'] as List),
      );

  Map<String, dynamic> toJson() => {
        'exists': exists,
        'not_exists': notExists,
      };
}

// ---------------------------------------------------------------------------
// Device DTOs
// ---------------------------------------------------------------------------

/// Request body for POST /devices/register.
class DeviceRegisterRequest {
  final String deviceId;
  final String deviceName;
  final String platform;

  const DeviceRegisterRequest({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
  });

  factory DeviceRegisterRequest.fromJson(Map<String, dynamic> json) =>
      DeviceRegisterRequest(
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String,
        platform: json['platform'] as String,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
      };
}

// ---------------------------------------------------------------------------
// Media / Album response DTOs
// ---------------------------------------------------------------------------

/// Paginated media list response data.
class MediaListResponse {
  final int total;
  final int page;
  final int pageSize;
  final List<MediaItem> items;

  const MediaListResponse({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.items,
  });

  factory MediaListResponse.fromJson(Map<String, dynamic> json) =>
      MediaListResponse(
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['page_size'] as int,
        items: (json['items'] as List)
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'total': total,
        'page': page,
        'page_size': pageSize,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

/// Album response DTO (used in album list endpoints).
class AlbumResponse {
  final String albumName;
  final String deviceId;
  final String? coverThumbnailUrl;
  final int mediaCount;

  const AlbumResponse({
    required this.albumName,
    required this.deviceId,
    this.coverThumbnailUrl,
    required this.mediaCount,
  });

  factory AlbumResponse.fromJson(Map<String, dynamic> json) => AlbumResponse(
        albumName: json['album_name'] as String,
        deviceId: json['device_id'] as String,
        coverThumbnailUrl: json['cover_thumbnail_url'] as String?,
        mediaCount: json['media_count'] as int,
      );

  Map<String, dynamic> toJson() => {
        'album_name': albumName,
        'device_id': deviceId,
        if (coverThumbnailUrl != null) 'cover_thumbnail_url': coverThumbnailUrl,
        'media_count': mediaCount,
      };
}
