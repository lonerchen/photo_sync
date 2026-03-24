import 'dart:async';
import 'dart:convert';

import 'package:common/common.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/i_server_database.dart';
import '../services/i_thumbnail_queue.dart';

/// Manages WebSocket connections from mobile devices.
///
/// Responsibilities:
/// - Maintains a [device_id → WebSocketChannel] map.
/// - Sends heartbeat every 15 s; marks device offline after 45 s silence.
/// - Handles incoming [WsEventType.heartbeatAck] and
///   [WsEventType.thumbnailPriority] events.
class WebSocketServer {
  WebSocketServer({
    required IServerDatabase database,
    required IThumbnailQueue thumbnailQueue,
  })  : _database = database,
        _thumbnailQueue = thumbnailQueue;

  final IServerDatabase _database;
  final IThumbnailQueue _thumbnailQueue;

  static const Duration _heartbeatInterval = Duration(seconds: 15);
  static const Duration _heartbeatTimeout = Duration(seconds: 45);

  /// Active connections: device_id → channel.
  final Map<String, WebSocketChannel> _connections = {};

  /// Last heartbeat-ack time per device.
  final Map<String, DateTime> _lastAck = {};

  /// Per-device stream subscriptions.
  final Map<String, StreamSubscription<dynamic>> _subscriptions = {};

  Timer? _heartbeatTimer;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts the heartbeat timer.
  void start() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _tick());
  }

  /// Stops the heartbeat timer and closes all connections.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final entry in _connections.entries) {
      _closeConnection(entry.key, entry.value);
    }
    _connections.clear();
    _lastAck.clear();
    _subscriptions.clear();
  }

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  /// Called when a new WebSocket connection arrives for [deviceId].
  void handleConnect(String deviceId, WebSocketChannel channel) {
    // Close any existing connection for this device.
    final existing = _connections[deviceId];
    if (existing != null) {
      _closeConnection(deviceId, existing);
    }

    _connections[deviceId] = channel;
    _lastAck[deviceId] = DateTime.now();

    _subscriptions[deviceId] = channel.stream.listen(
      (message) => _onMessage(deviceId, message),
      onDone: () => _onDisconnect(deviceId),
      onError: (_) => _onDisconnect(deviceId),
      cancelOnError: true,
    );

    _database.setDeviceConnected(deviceId, connected: true);
  }

  void _onDisconnect(String deviceId) {
    _subscriptions.remove(deviceId)?.cancel();
    _connections.remove(deviceId);
    _lastAck.remove(deviceId);
    _database.setDeviceConnected(deviceId, connected: false);
  }

  void _closeConnection(String deviceId, WebSocketChannel channel) {
    _subscriptions.remove(deviceId)?.cancel();
    channel.sink.close();
  }

  // ---------------------------------------------------------------------------
  // Incoming message handling
  // ---------------------------------------------------------------------------

  void _onMessage(String deviceId, dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final msg = WsMessage.fromJson(json);

      switch (msg.type) {
        case WsEventType.heartbeatAck:
          _lastAck[deviceId] = DateTime.now();

        case WsEventType.thumbnailPriority:
          final mediaId = msg.data['media_id'] as int?;
          if (mediaId != null) {
            _thumbnailQueue.enqueuePriority(mediaId);
          }

        case WsEventType.disconnect:
          _onDisconnect(deviceId);
      }
    } catch (_) {
      // Ignore malformed messages.
    }
  }

  // ---------------------------------------------------------------------------
  // Heartbeat tick
  // ---------------------------------------------------------------------------

  void _tick() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;

    final timedOut = <String>[];

    for (final deviceId in List<String>.from(_connections.keys)) {
      final lastAck = _lastAck[deviceId];
      if (lastAck != null &&
          now.difference(lastAck) > _heartbeatTimeout) {
        timedOut.add(deviceId);
        continue;
      }

      // Send heartbeat.
      _sendTo(deviceId, WsMessage(
        type: WsEventType.heartbeat,
        data: {'timestamp': timestamp},
      ));
    }

    for (final deviceId in timedOut) {
      final channel = _connections.remove(deviceId);
      if (channel != null) _closeConnection(deviceId, channel);
      _lastAck.remove(deviceId);
      _database.setDeviceConnected(deviceId, connected: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Broadcast helpers
  // ---------------------------------------------------------------------------

  /// Sends [message] to the device with [deviceId] (if connected).
  void broadcast(String deviceId, WsMessage message) {
    _sendTo(deviceId, message);
  }

  /// Sends [message] to all connected devices.
  void broadcastAll(WsMessage message) {
    for (final deviceId in List<String>.from(_connections.keys)) {
      _sendTo(deviceId, message);
    }
  }

  void _sendTo(String deviceId, WsMessage message) {
    final channel = _connections[deviceId];
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message.toJson()));
    } catch (_) {
      // Connection may have closed; ignore.
    }
  }
}
