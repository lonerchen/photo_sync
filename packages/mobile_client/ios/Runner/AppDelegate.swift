import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register the Live Photo platform channel (16.3 / 16.4).
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.photosync/live_photo",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "saveLivePhoto" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let heicPath = args["heicPath"] as? String,
          let movPath = args["movPath"] as? String
        else {
          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "heicPath and movPath are required",
              details: nil
            )
          )
          return
        }
        self?.saveLivePhoto(heicPath: heicPath, movPath: movPath, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Live Photo save (16.4)

  private func saveLivePhoto(heicPath: String, movPath: String, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized else {
        result(
          FlutterError(
            code: "PERMISSION_DENIED",
            message: "Photo library access denied",
            details: nil
          )
        )
        return
      }

      PHPhotoLibrary.shared().performChanges({
        let creationRequest = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false

        creationRequest.addResource(
          with: .photo,
          fileURL: URL(fileURLWithPath: heicPath),
          options: options
        )
        creationRequest.addResource(
          with: .pairedVideo,
          fileURL: URL(fileURLWithPath: movPath),
          options: options
        )
      }) { success, error in
        if success {
          result(true)
        } else {
          result(
            FlutterError(
              code: "SAVE_FAILED",
              message: error?.localizedDescription ?? "Unknown error",
              details: nil
            )
          )
        }
      }
    }
  }
}
