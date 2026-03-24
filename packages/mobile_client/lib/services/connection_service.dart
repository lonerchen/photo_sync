import 'dart:async';
import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../database/mobile_database.dart';

/// Connection lifecycle states.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Manages the WebSocket connection to a storage server.
///
/// State machine:
///   DISCONNECTED → CONNECTING → CONNECTED → RECONNECTING → CONNECTED
///                                                        ↘ DISCONNECTED
class ConnectionService extends ChangeNotifier {
  static const _maxReconnectAttempts = 3;
  static const _reconnectInterval = Duration(seconds: 5);
  static const _heartbeatTimeout = Duration(seconds: 45);

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ServerInfo? _currentServer;
  String? _deviceId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final _messageController = StreamController<WsMessage>.broadcast();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  ConnectionStatus get status => _status;
  ServerInfo? get currentServer => _currentServer;

  /// Broadcasts all incoming WebSocket messages.
  Stream<WsMessage> get messageStream => _messageController.stream;

  /// Registers the device via HTTP and opens a WebSocket connection.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> connect(ServerInfo server, String deviceId) async {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return false;
    }

    _currentServer = server;
    _deviceId = deviceId;
    _reconnectAttempts = 0;
    return _doConnect();
  }

  /// Sends a graceful disconnect event and closes the WebSocket.
  void disconnect() {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect.
    _sendDisconnectEvent();
    _closeConnection();
    _setStatus(ConnectionStatus.disconnected);
    _currentServer = null;
    _deviceId = null;
  }

  /// Sends a [WsMessage] to the server.
  void sendMessage(WsMessage message) {
    if (_status != ConnectionStatus.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
    } catch (_) {
      // Ignore send errors; heartbeat timeout will trigger reconnect.
    }
  }

  /// Reads the last connected server from [db] and attempts to connect.
  Future<void> tryAutoConnect(MobileDatabase db, String deviceId) async {
    final server = await db.connectedServersDao.getLastConnectedServer();
    if (server == null) return;
    await connect(server, deviceId);
  }

  // ---------------------------------------------------------------------------
  // Internal connection logic
  // ---------------------------------------------------------------------------

  Future<bool> _doConnect() async {
    _setStatus(ConnectionStatus.connecting);

    final server = _currentServer!;
    final deviceId = _deviceId!;

    // 1. Register device via HTTP.
    final registered = await _registerDevice(server, deviceId);
    if (!registered) {
      _handleConnectFailure();
      return false;
    }

    // 2. Open WebSocket.
    final wsUrl =
        'ws://${server.ipAddress}:${server.port}/ws?device_id=$deviceId';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
    } catch (_) {
      _handleConnectFailure();
      return false;
    }

    _setStatus(ConnectionStatus.connected);
    _reconnectAttempts = 0;
    _startListening();
    _resetHeartbeatTimer();
    return true;
  }

  Future<bool> _registerDevice(ServerInfo server, String deviceId) async {
    try {
      final uri = Uri.parse(
          'http://${server.ipAddress}:${server.port}/api/v1/devices/register');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_id': deviceId,
              'device_name': deviceId,
              'platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void _startListening() {
    _wsSub?.cancel();
    _wsSub = _channel!.stream.listen(
      _onMessage,
      onError: (_) => _onConnectionLost(),
      onDone: _onConnectionLost,
    );
  }

  void _onMessage(dynamic raw) {
    _resetHeartbeatTimer();
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final msg = WsMessage.fromJson(json);

      if (msg.type == WsEventType.heartbeat) {
        // Reply with heartbeat_ack carrying the same timestamp.
        sendMessage(WsMessage(
          type: WsEventType.heartbeatAck,
          data: {'timestamp': msg.data['timestamp']},
        ));
      }

      if (!_messageController.isClosed) {
        _messageController.add(msg);
      }
    } catch (_) {
      // Malformed message; ignore.
    }
  }

  void _onConnectionLost() {
    if (_status == ConnectionStatus.disconnected) return;
    _closeConnection(keepServer: true);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setStatus(ConnectionStatus.disconnected);
      _currentServer = null;
      _deviceId = null;
      return;
    }

    _setStatus(ConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () async {
      _reconnectAttempts++;
      final success = await _doConnect();
      if (!success && _reconnectAttempts < _maxReconnectAttempts) {
        _scheduleReconnect();
      }
    });
  }

  void _resetHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(_heartbeatTimeout, _onConnectionLost);
  }

  void _handleConnectFailure() {
    _closeConnection(keepServer: true);
    _scheduleReconnect();
  }

  void _sendDisconnectEvent() {
    if (_channel == null) return;
    try {
      _channel!.sink
          .add(jsonEncode(WsMessage(type: WsEventType.disconnect).toJson()));
    } catch (_) {}
  }

  void _closeConnection({bool keepServer = false}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    if (!keepServer) {
      _currentServer = null;
      _deviceId = null;
    }
  }

  void _setStatus(ConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
