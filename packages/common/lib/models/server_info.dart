/// Represents a storage server discovered on the LAN.
class ServerInfo {
  final String serverId;
  final String serverName;
  final String ipAddress;
  final int port;

  const ServerInfo({
    required this.serverId,
    required this.serverName,
    required this.ipAddress,
    required this.port,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        serverId: json['server_id'] as String,
        serverName: json['server_name'] as String,
        ipAddress: json['ip_address'] as String,
        port: json['port'] as int,
      );

  Map<String, dynamic> toJson() => {
        'server_id': serverId,
        'server_name': serverName,
        'ip_address': ipAddress,
        'port': port,
      };

  /// Base URL for HTTP API calls.
  String get baseUrl => 'http://$ipAddress:$port/api/v1';
}
