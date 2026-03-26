import BackgroundTasks
import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Background task identifier for upload continuation
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
  private static let bgUploadTaskId = "com.loner.photosync.upload"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // ── Register BGTask identifier (required when UIBackgroundModes includes 'processing') ──
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: AppDelegate.bgUploadTaskId,
      using: nil
    ) { task in
      // We use UIBackgroundTask for actual upload continuation, not BGProcessingTask.
      // This registration satisfies the BGTaskSchedulerPermittedIdentifiers requirement.
      task.setTaskCompleted(success: true)
    }

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── Live Photo channel ──────────────────────────────────────────────────
    let livePhotoChannel = FlutterMethodChannel(
      name: "com.loner.photosync/live_photo",
      binaryMessenger: controller.binaryMessenger
    )
    livePhotoChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveLivePhoto" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let heicPath = args["heicPath"] as? String,
        let movPath = args["movPath"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "heicPath and movPath are required", details: nil))
        return
      }
      self?.saveLivePhoto(heicPath: heicPath, movPath: movPath, result: result)
    }

    // ── Background transfer channel ─────────────────────────────────────────
    let bgChannel = FlutterMethodChannel(
      name: "com.loner.photosync/background_transfer",
      binaryMessenger: controller.binaryMessenger
    )
    bgChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "beginBackgroundTask":
        self?.beginUploadBackgroundTask()
        result(nil)
      case "endBackgroundTask":
        self?.endUploadBackgroundTask()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Background task management

  private func beginUploadBackgroundTask() {
    guard bgTaskId == .invalid else { return }
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "PhotoUpload") { [weak self] in
      // Expiry handler — iOS is about to suspend; end the task gracefully
      self?.endUploadBackgroundTask()
    }
  }

  private func endUploadBackgroundTask() {
    guard bgTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(bgTaskId)
    bgTaskId = .invalid
  }

  // MARK: - Live Photo save

  private func saveLivePhoto(heicPath: String, movPath: String, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized else {
        result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library access denied", details: nil))
        return
      }

      PHPhotoLibrary.shared().performChanges({
        let creationRequest = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false
        creationRequest.addResource(with: .photo, fileURL: URL(fileURLWithPath: heicPath), options: options)
        creationRequest.addResource(with: .pairedVideo, fileURL: URL(fileURLWithPath: movPath), options: options)
      }) { success, error in
        if success {
          result(true)
        } else {
          result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription ?? "Unknown error", details: nil))
        }
      }
    }
  }
}
