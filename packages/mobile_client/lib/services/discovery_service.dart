import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// Discovers storage servers on the LAN via mDNS and UDP broadcast.
///
/// Results are deduplicated by [ServerInfo.serverId] and exposed as a
/// [Stream<List<ServerInfo>>] and also via [ChangeNotifier].
class DiscoveryService extends ChangeNotifier {
  static const _mdnsServiceType = '_photosync._tcp';
  static const _udpPort = 8766;

  final _servers = <String, ServerInfo>{};

  MDnsClient? _mdnsClient;
  RawDatagramSocket? _udpSocket;
  Timer? _mdnsTimer;
  bool _running = false;

  /// Current snapshot of discovered servers.
  List<ServerInfo> get servers => List.unmodifiable(_servers.values);

  /// Starts mDNS and UDP broadcast discovery.
  Future<void> startDiscovery() async {
    if (_running) return;
    _running = true;

    await _startUdpListener();
    // iOS/macOS/Windows/Linux 使用 mDNS 扫描；Android 继续走 UDP 广播兜底。
    // iOS 上 mDNS 查询也是触发本地网络权限弹窗的关键路径。
    if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      await _startMdnsDiscovery();
    }
  }

  /// Stops all discovery and releases resources.
  void stopDiscovery() {
    _running = false;
    _mdnsTimer?.cancel();
    _mdnsTimer = null;
    _mdnsClient?.stop();
    _mdnsClient = null;
    _udpSocket?.close();
    _udpSocket = null;
  }

  // ---------------------------------------------------------------------------
  // mDNS
  // ---------------------------------------------------------------------------

  Future<void> _startMdnsDiscovery() async {
    await _scanMdnsSafely();
    // iOS 上 mDNS 主要用于首次触发本地网络权限，不做周期轮询，避免在弱网/
    // 无路由场景反复触发 socket 异常日志；后续依赖 UDP 广播持续发现。
    if (Platform.isIOS) return;
    _mdnsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_running) return;
      unawaited(_scanMdnsSafely());
    });
  }

  Future<void> _scanMdnsSafely() async {
    try {
      await _runMdnsScan();
    } catch (_) {
      // Never bubble mDNS errors to upper async zones.
    }
  }

  Future<void> _runMdnsScan() async {
    _mdnsClient?.stop();
    _mdnsClient = MDnsClient();
    try {
      await _mdnsClient!.start();
      await for (final PtrResourceRecord ptr in _safeLookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_mdnsServiceType),
      )) {
        await for (final SrvResourceRecord srv in _safeLookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final IPAddressResourceRecord ip in _safeLookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            final serverId = ptr.domainName;
            final serverName = ptr.domainName.split('.').first;
            _addOrUpdate(ServerInfo(
              serverId: serverId,
              serverName: serverName,
              ipAddress: ip.address.address,
              port: srv.port,
            ));
          }
        }
      }
    } catch (_) {
      // Ignore mDNS errors; UDP broadcast is the fallback.
    } finally {
      _mdnsClient?.stop();
      _mdnsClient = null;
    }
  }

  Stream<T> _safeLookup<T extends ResourceRecord>(ResourceRecordQuery query) {
    try {
      final client = _mdnsClient;
      if (client == null) return const Stream.empty();
      return client.lookup<T>(query).handleError((Object _, StackTrace __) {
        // Ignore mDNS lookup errors and continue using UDP fallback.
      });
    } catch (_) {
      // On some iOS network states lookup() can throw synchronously.
      return const Stream.empty();
    }
  }

  // ---------------------------------------------------------------------------
  // UDP broadcast
  // ---------------------------------------------------------------------------

  Future<void> _startUdpListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
      );
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) _handleUdpDatagram(datagram);
        }
      });
    } catch (_) {
      // UDP may not be available on all platforms; ignore.
    }
  }

  void _handleUdpDatagram(Datagram datagram) {
    try {
      final json =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (json['type'] != 'server_announce') return;

      _addOrUpdate(ServerInfo(
        serverId: json['server_id'] as String,
        serverName: json['server_name'] as String,
        ipAddress: json['ip'] as String,
        port: json['port'] as int,
      ));
    } catch (_) {
      // Malformed packet; ignore.
    }
  }

  void _addOrUpdate(ServerInfo info) {
    _servers[info.serverId] = info;
    notifyListeners();
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}
