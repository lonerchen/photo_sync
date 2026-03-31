import BackgroundTasks
import Flutter
import Network
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Background task identifier for upload continuation
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
  private static let bgUploadTaskId = "com.loner.photosync.upload"
  private var localNetworkBrowser: NWBrowser?
  private var localNetworkService: NetService?
  private var localNetworkTimer: Timer?
  private var localNetworkPendingResult: FlutterResult?

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

    // ── Local network permission channel ────────────────────────────────────
    let localNetworkChannel = FlutterMethodChannel(
      name: "com.loner.photosync/local_network",
      binaryMessenger: controller.binaryMessenger
    )
    localNetworkChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "requestPermission":
        self.requestLocalNetworkPermission(result: result)
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
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

  // MARK: - Local Network permission

  private func requestLocalNetworkPermission(result: @escaping FlutterResult) {
    if #available(iOS 14.0, *) {
      if localNetworkPendingResult != nil {
        result("requesting")
        return
      }
      localNetworkPendingResult = result

      let params = NWParameters()
      params.includePeerToPeer = true

      let browser = NWBrowser(
        for: .bonjour(type: "_photosync._tcp", domain: nil),
        using: params
      )
      localNetworkBrowser = browser

      browser.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.finishLocalNetworkPermission(status: "granted")
        case .waiting(let error):
          if case .posix(let code) = error, code == .EPERM {
            self.finishLocalNetworkPermission(status: "denied")
          }
        case .failed:
          self.finishLocalNetworkPermission(status: "unknown")
        default:
          break
        }
      }

      browser.browseResultsChangedHandler = { [weak self] _, _ in
        self?.finishLocalNetworkPermission(status: "granted")
      }

      let service = NetService(
        domain: "local.",
        type: "_photosync._tcp.",
        name: "PhotoSyncProbe-\(UUID().uuidString)",
        port: 9
      )
      localNetworkService = service
      service.publish(options: .listenForConnections)

      browser.start(queue: .main)

      localNetworkTimer?.invalidate()
      localNetworkTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
        self?.finishLocalNetworkPermission(status: "unknown")
      }
    } else {
      result("granted")
    }
  }

  private func finishLocalNetworkPermission(status: String) {
    localNetworkTimer?.invalidate()
    localNetworkTimer = nil
    localNetworkBrowser?.cancel()
    localNetworkBrowser = nil
    localNetworkService?.stop()
    localNetworkService = nil

    if let callback = localNetworkPendingResult {
      callback(status)
      localNetworkPendingResult = nil
    }
  }
}
