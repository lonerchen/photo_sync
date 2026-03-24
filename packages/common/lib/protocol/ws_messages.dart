/// A WebSocket message envelope.
///
/// All messages follow the format: `{"type": "...", "data": {...}}`
class WsMessage {
  final String type;
  final Map<String, dynamic> data;

  const WsMessage({
    required this.type,
    this.data = const {},
  });

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
        type: json['type'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
      };
}

/// WebSocket event type constants.
///
/// Server → Client events and Client → Server events.
abstract final class WsEventType {
  // -------------------------------------------------------------------------
  // Server → Client
  // -------------------------------------------------------------------------

  /// Thumbnail generation completed for a media item.
  /// data: `{"media_id": int, "thumbnail_url": String}`
  static const String thumbnailReady = 'thumbnail_ready';

  /// Upload progress update for a file.
  /// data: `{"file_name": String, "uploaded_bytes": int, "total_size": int}`
  static const String uploadProgress = 'upload_progress';

  /// Heartbeat keep-alive (every 15 seconds).
  /// data: `{"timestamp": int}`
  static const String heartbeat = 'heartbeat';

  /// Server status change notification.
  /// data: `{"status": String, "progress": int?}`
  static const String serverStatus = 'server_status';

  // -------------------------------------------------------------------------
  // Client → Server
  // -------------------------------------------------------------------------

  /// Heartbeat acknowledgement from client.
  /// data: `{"timestamp": int}`
  static const String heartbeatAck = 'heartbeat_ack';

  /// Request priority thumbnail generation for a media item.
  /// data: `{"media_id": int}`
  static const String thumbnailPriority = 'thumbnail_priority';

  /// Client is disconnecting gracefully.
  /// data: `{}`
  static const String disconnect = 'disconnect';
}
