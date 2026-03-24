/// Represents a connected mobile device.
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final bool isConnected;
  final String storagePath;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.isConnected,
    required this.storagePath,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String,
        platform: json['platform'] as String,
        isConnected: (json['is_connected'] as int) != 0,
        storagePath: json['storage_path'] as String,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'is_connected': isConnected ? 1 : 0,
        'storage_path': storagePath,
      };
}
