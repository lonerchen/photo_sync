import 'dart:io';

import 'package:flutter/services.dart';

enum LocalNetworkPermissionStatus {
  unknown,
  requesting,
  granted,
  denied,
}

class LocalNetworkPermissionService {
  static const MethodChannel _channel =
      MethodChannel('com.loner.photosync/local_network');

  Future<LocalNetworkPermissionStatus> requestPermission() async {
    if (!Platform.isIOS) return LocalNetworkPermissionStatus.granted;
    try {
      final status = await _channel.invokeMethod<String>('requestPermission');
      return _parse(status);
    } catch (_) {
      return LocalNetworkPermissionStatus.unknown;
    }
  }

  Future<void> openSettings() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  LocalNetworkPermissionStatus _parse(String? raw) {
    switch (raw) {
      case 'granted':
        return LocalNetworkPermissionStatus.granted;
      case 'denied':
        return LocalNetworkPermissionStatus.denied;
      case 'requesting':
        return LocalNetworkPermissionStatus.requesting;
      default:
        return LocalNetworkPermissionStatus.unknown;
    }
  }
}
