import 'package:common/common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Data-access object for the `connected_devices` table.
class ConnectedDevicesDao {
  final Database _db;

  ConnectedDevicesDao(this._db);

  // ---------------------------------------------------------------------------
  // Insert / upsert
  // ---------------------------------------------------------------------------

  /// Inserts a brand-new device record (no conflict handling).
  Future<void> insertDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String storagePath,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('connected_devices', {
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'storage_path': storagePath,
      'is_connected': 1,
      'last_connected_at': now,
      'created_at': now,
    });
  }

  /// Registers or updates a device. Returns the stored [DeviceInfo].
  Future<DeviceInfo> registerDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String storagePath,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.execute('''
      INSERT INTO connected_devices
        (device_id, device_name, platform, storage_path, is_connected,
         last_connected_at, created_at)
      VALUES (?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        device_name = excluded.device_name,
        platform = excluded.platform,
        storage_path = excluded.storage_path,
        is_connected = 1,
        last_connected_at = excluded.last_connected_at
    ''', [deviceId, deviceName, platform, storagePath, now, now]);

    return (await getDevice(deviceId))!;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Future<List<DeviceInfo>> getAllDevices() async {
    final rows = await _db.query('connected_devices');
    return rows.map(_rowToDeviceInfo).toList();
  }

  Future<DeviceInfo?> getDevice(String deviceId) async {
    final rows = await _db.query(
      'connected_devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToDeviceInfo(rows.first);
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  Future<void> setDeviceConnected(String deviceId, {required bool connected}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'connected_devices',
      {
        'is_connected': connected ? 1 : 0,
        if (connected) 'last_connected_at': now,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> deleteDevice(String deviceId) async {
    await _db.delete(
      'connected_devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static DeviceInfo _rowToDeviceInfo(Map<String, dynamic> row) => DeviceInfo(
        deviceId: row['device_id'] as String,
        deviceName: row['device_name'] as String,
        platform: row['platform'] as String,
        isConnected: (row['is_connected'] as int) != 0,
        storagePath: row['storage_path'] as String,
      );
}
