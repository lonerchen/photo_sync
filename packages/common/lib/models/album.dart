/// Represents a photo album on the storage server.
class Album {
  final String albumName;
  final String deviceId;
  final String? coverThumbnailUrl;
  final int mediaCount;

  const Album({
    required this.albumName,
    required this.deviceId,
    this.coverThumbnailUrl,
    required this.mediaCount,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
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
