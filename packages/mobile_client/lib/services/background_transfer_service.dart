import 'dart:io';

import 'package:flutter/services.dart';

/// Manages platform-level background execution for upload tasks.
///
/// - iOS: calls `beginBackgroundTask` / `endBackgroundTask` via UIApplication,
///   giving ~30 seconds of extra execution time after the app is backgrounded.
/// - Android: starts/stops a Foreground Service with a persistent notification,
///   keeping the process alive while uploading.
/// - Desktop: no-op (desktop has no background execution restrictions).
class BackgroundTransferService {
  static const _channel = MethodChannel('com.loner.photosync/background_transfer');

  static final BackgroundTransferService _instance =
      BackgroundTransferService._();
  factory BackgroundTransferService() => _instance;
  BackgroundTransferService._();

  bool _active = false;

  /// Call when upload starts. Safe to call multiple times (idempotent).
  Future<void> begin() async {
    if (_active) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('beginBackgroundTask');
      _active = true;
    } catch (_) {
      // Non-fatal: upload continues in foreground
    }
  }

  /// Call when upload finishes or is cancelled.
  Future<void> end() async {
    if (!_active) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('endBackgroundTask');
    } catch (_) {}
    _active = false;
  }
}
