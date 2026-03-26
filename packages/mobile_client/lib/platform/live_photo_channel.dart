import 'package:flutter/services.dart';

/// Platform channel for saving Live Photos on iOS.
///
/// Wraps the native `com.loner.photosync/live_photo` MethodChannel.
class LivePhotoChannel {
  static const _channel = MethodChannel('com.loner.photosync/live_photo');

  /// Saves a Live Photo to the system photo library.
  ///
  /// [heicPath] – path to the HEIC still image (temp file).
  /// [movPath]  – path to the paired MOV video (temp file).
  ///
  /// Returns `true` on success, throws [PlatformException] on failure.
  static Future<bool> saveLivePhoto({
    required String heicPath,
    required String movPath,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'saveLivePhoto',
      {'heicPath': heicPath, 'movPath': movPath},
    );
    return result ?? false;
  }
}
