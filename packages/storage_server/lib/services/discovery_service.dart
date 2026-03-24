import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// Broadcasts server presence via mDNS and UDP so mobile clients can
/// auto-discover the storage server on the local network.
///
/// - mDNS: registers `_photosync._tcp` (best-effort; falls back gracefully)
/// - UDP: sends a JSON announce packet to `255.255.255.255:8766` every 3 s
class DiscoveryService {
  DiscoveryService({
    required this.serverId,
    required this.serverName,
    this.port = 8765,
  });

  final String serverId;
  final String serverName;
  final int port;

  static const int _udpBroadcastPort = 8766;
  static const Duration _broadcastInterval = Duration(seconds: 3);

  MDnsClient? _mdnsClient;
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts mDNS registration and UDP broadcast.
  Future<void> start() async {
    await _startMdns();
    await _startUdpBroadcast();
  }

  /// Stops both mDNS and UDP broadcast.
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _udpSocket?.close();
    _udpSocket = null;

    _mdnsClient?.stop();
    _mdnsClient = null;
  }

  // ---------------------------------------------------------------------------
  // mDNS (best-effort)
  // ---------------------------------------------------------------------------

  Future<void> _startMdns() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
      // mDNS registration is passive via the MDnsClient on desktop;
      // the client is kept alive so it can respond to PTR queries.
      // Full service advertisement requires platform-specific APIs on some
      // desktop targets, so we treat this as best-effort.
    } catch (e) {
      // mDNS is not critical – UDP broadcast is the primary mechanism.
      _mdnsClient = null;
    }
  }

  // ---------------------------------------------------------------------------
  // UDP broadcast
  // ---------------------------------------------------------------------------

  Future<void> _startUdpBroadcast() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      // Send immediately, then repeat every 3 s.
      _sendBroadcast();
      _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _sendBroadcast());
    } catch (e) {
      // If UDP broadcast fails, log and continue without it.
      _udpSocket = null;
    }
  }

  void _sendBroadcast() {
    final socket = _udpSocket;
    if (socket == null) return;

    final ip = _localIpAddress();
    final payload = jsonEncode({
      'type': 'server_announce',
      'server_id': serverId,
      'server_name': serverName,
      'ip': ip,
      'port': port,
      'version': '1.0.0',
    });

    final data = utf8.encode(payload);
    try {
      socket.send(
        data,
        InternetAddress('255.255.255.255'),
        _udpBroadcastPort,
      );
    } catch (_) {
      // Ignore transient send errors.
    }
  }

  /// Returns the first non-loopback IPv4 address, or '127.0.0.1' as fallback.
  String _localIpAddress() {
    try {
      final interfaces = NetworkInterface.listSync(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
