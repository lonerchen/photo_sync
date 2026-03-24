/// Media type for uploaded files.
enum MediaType {
  image,
  video,
  livePhoto;

  String toJson() => switch (this) {
        MediaType.image => 'image',
        MediaType.video => 'video',
        MediaType.livePhoto => 'live_photo',
      };

  static MediaType fromJson(String value) => switch (value) {
        'image' => MediaType.image,
        'video' => MediaType.video,
        'live_photo' => MediaType.livePhoto,
        _ => throw ArgumentError('Unknown MediaType: $value'),
      };
}

/// Thumbnail generation status.
enum ThumbnailStatus {
  pending,
  generating,
  ready,
  failed;

  String toJson() => name;

  static ThumbnailStatus fromJson(String value) => switch (value) {
        'pending' => ThumbnailStatus.pending,
        'generating' => ThumbnailStatus.generating,
        'ready' => ThumbnailStatus.ready,
        'failed' => ThumbnailStatus.failed,
        _ => throw ArgumentError('Unknown ThumbnailStatus: $value'),
      };
}

/// Represents a single media item (photo, video, or live photo) stored on the server.
class MediaItem {
  final int id;
  final String deviceId;
  final String fileName;
  final String albumName;
  final String filePath;
  final int fileSize;
  final MediaType mediaType;
  final int? takenAt;
  final String? thumbnailPath;
  final ThumbnailStatus thumbnailStatus;
  final String? livePhotoPairName;
  final int createdAt;
  final int updatedAt;

  const MediaItem({
    required this.id,
    required this.deviceId,
    required this.fileName,
    required this.albumName,
    required this.filePath,
    required this.fileSize,
    required this.mediaType,
    this.takenAt,
    this.thumbnailPath,
    required this.thumbnailStatus,
    this.livePhotoPairName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as int,
        deviceId: json['device_id'] as String,
        fileName: json['file_name'] as String,
        albumName: json['album_name'] as String,
        filePath: json['file_path'] as String,
        fileSize: json['file_size'] as int,
        mediaType: MediaType.fromJson(json['media_type'] as String),
        takenAt: json['taken_at'] as int?,
        thumbnailPath: json['thumbnail_path'] as String?,
        thumbnailStatus: ThumbnailStatus.fromJson(
          json['thumbnail_status'] as String? ?? 'pending',
        ),
        livePhotoPairName: json['live_photo_pair_name'] as String?,
        createdAt: json['created_at'] as int,
        updatedAt: json['updated_at'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'file_name': fileName,
        'album_name': albumName,
        'file_path': filePath,
        'file_size': fileSize,
        'media_type': mediaType.toJson(),
        if (takenAt != null) 'taken_at': takenAt,
        if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
        'thumbnail_status': thumbnailStatus.toJson(),
        if (livePhotoPairName != null) 'live_photo_pair_name': livePhotoPairName,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
