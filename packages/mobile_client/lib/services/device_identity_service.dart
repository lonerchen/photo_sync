import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Provides a stable-ish device id and a user-friendly device name.
///
/// The values are cached in-memory to avoid repeated plugin calls.
class DeviceIdentityService {
  DeviceIdentityService._();

  static final DeviceIdentityService instance = DeviceIdentityService._();

  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();
  Future<DeviceIdentity>? _loading;
  DeviceIdentity? _cached;

  Future<DeviceIdentity> getIdentity() async {
    if (_cached != null) return _cached!;
    _loading ??= _loadIdentity();
    _cached = await _loading!;
    return _cached!;
  }

  Future<String> getDeviceId() async => (await getIdentity()).deviceId;

  Future<String> getDeviceName() async => (await getIdentity()).deviceName;

  Future<DeviceIdentity> _loadIdentity() async {
    try {
      if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        final rawId = (info.identifierForVendor != null &&
                info.identifierForVendor!.trim().isNotEmpty)
            ? info.identifierForVendor!
            : info.utsname.machine;
        final rawName = info.name.trim().isNotEmpty
            ? info.name
            : (info.model.trim().isNotEmpty ? info.model : 'iPhone');
        return DeviceIdentity(
          deviceId: _sanitize(rawId),
          deviceName: rawName,
          platform: 'ios',
        );
      }

      if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        final rawId = '${info.id}_${info.model}_${info.device}';
        final brand = info.brand.trim();
        final model = info.model.trim();
        final rawName = '$brand $model'.trim().replaceAll(RegExp(r'\s+'), ' ');
        return DeviceIdentity(
          deviceId: _sanitize(rawId.isNotEmpty ? rawId : 'android_device'),
          deviceName: rawName.isNotEmpty ? rawName : 'Android Device',
          platform: 'android',
        );
      }
    } catch (_) {
      // Plugin may fail on first load; fall through to fallback.
    }

    final fallbackPlatform = Platform.isIOS ? 'ios' : 'android';
    return DeviceIdentity(
      deviceId: fallbackPlatform == 'ios' ? 'ios_device' : 'android_device',
      deviceName: fallbackPlatform == 'ios' ? 'iPhone' : 'Android Device',
      platform: fallbackPlatform,
    );
  }

  String _sanitize(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'mobile_device' : cleaned;
  }
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
}
