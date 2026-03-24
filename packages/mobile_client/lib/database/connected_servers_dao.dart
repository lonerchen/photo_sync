import 'package:common/common.dart';
import 'package:sqflite/sqflite.dart';

/// Data-access object for the `connected_servers` table.
class ConnectedServersDao {
  final Database _db;

  ConnectedServersDao(this._db);

  // ---------------------------------------------------------------------------
  // Insert / upsert
  // ---------------------------------------------------------------------------

  /// Inserts or updates a server record by [ServerInfo.serverId].
  Future<void> upsertServer(ServerInfo server) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.execute('''
      INSERT INTO connected_servers
        (server_id, server_name, ip_address, port, last_connected_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_id) DO UPDATE SET
        server_name = excluded.server_name,
        ip_address = excluded.ip_address,
        port = excluded.port,
        last_connected_at = excluded.last_connected_at
    ''', [
      server.serverId,
      server.serverName,
      server.ipAddress,
      server.port,
      now,
      now,
    ]);
  }

  /// Updates [last_connected_at] to now for the given [serverId].
  Future<void> updateLastConnected(String serverId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'connected_servers',
      {'last_connected_at': now},
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the server with the most recent [last_connected_at], or null.
  Future<ServerInfo?> getLastConnectedServer() async {
    final rows = await _db.query(
      'connected_servers',
      orderBy: 'last_connected_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToServerInfo(rows.first);
  }

  /// Returns all known servers ordered by most recently connected first.
  Future<List<ServerInfo>> getAllServers() async {
    final rows = await _db.query(
      'connected_servers',
      orderBy: 'last_connected_at DESC',
    );
    return rows.map(_rowToServerInfo).toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static ServerInfo _rowToServerInfo(Map<String, dynamic> row) => ServerInfo(
        serverId: row['server_id'] as String,
        serverName: row['server_name'] as String,
        ipAddress: row['ip_address'] as String,
        port: row['port'] as int,
      );
}
