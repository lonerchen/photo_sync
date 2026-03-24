import 'media_item.dart';

/// Status of an upload task.
enum TaskStatus {
  pending,
  uploading,
  paused,
  completed,
  failed;

  String toJson() => name;

  static TaskStatus fromJson(String value) => switch (value) {
        'pending' => TaskStatus.pending,
        'uploading' => TaskStatus.uploading,
        'paused' => TaskStatus.paused,
        'completed' => TaskStatus.completed,
        'failed' => TaskStatus.failed,
        _ => throw ArgumentError('Unknown TaskStatus: $value'),
      };
}

/// Represents a file upload task with resume support.
class UploadTask {
  final int? id;
  final String serverId;
  final String fileName;
  final String albumName;
  final String localAssetId;
  final int totalSize;
  final int uploadedBytes;
  final int chunkSize;
  final TaskStatus taskStatus;
  final MediaType mediaType;
  final String? livePhotoPairName;
  final int createdAt;
  final int updatedAt;

  const UploadTask({
    this.id,
    required this.serverId,
    required this.fileName,
    required this.albumName,
    required this.localAssetId,
    required this.totalSize,
    this.uploadedBytes = 0,
    required this.chunkSize,
    required this.taskStatus,
    required this.mediaType,
    this.livePhotoPairName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UploadTask.fromJson(Map<String, dynamic> json) => UploadTask(
        id: json['id'] as int?,
        serverId: json['server_id'] as String,
        fileName: json['file_name'] as String,
        albumName: json['album_name'] as String,
        localAssetId: json['local_asset_id'] as String,
        totalSize: json['total_size'] as int,
        uploadedBytes: json['uploaded_bytes'] as int? ?? 0,
        chunkSize: json['chunk_size'] as int,
        taskStatus: TaskStatus.fromJson(json['task_status'] as String),
        mediaType: MediaType.fromJson(json['media_type'] as String),
        livePhotoPairName: json['live_photo_pair_name'] as String?,
        createdAt: json['created_at'] as int,
        updatedAt: json['updated_at'] as int,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'server_id': serverId,
        'file_name': fileName,
        'album_name': albumName,
        'local_asset_id': localAssetId,
        'total_size': totalSize,
        'uploaded_bytes': uploadedBytes,
        'chunk_size': chunkSize,
        'task_status': taskStatus.toJson(),
        'media_type': mediaType.toJson(),
        if (livePhotoPairName != null) 'live_photo_pair_name': livePhotoPairName,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  UploadTask copyWith({
    int? totalSize,
    int? uploadedBytes,
    TaskStatus? taskStatus,
    int? updatedAt,
  }) =>
      UploadTask(
        id: id,
        serverId: serverId,
        fileName: fileName,
        albumName: albumName,
        localAssetId: localAssetId,
        totalSize: totalSize ?? this.totalSize,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        chunkSize: chunkSize,
        taskStatus: taskStatus ?? this.taskStatus,
        mediaType: mediaType,
        livePhotoPairName: livePhotoPairName,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
