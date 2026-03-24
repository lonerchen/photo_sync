package com.photosync.mobile_client

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.photosync/background_transfer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "beginBackgroundTask" -> {
                        startUploadService()
                        result.success(null)
                    }
                    "endBackgroundTask" -> {
                        stopUploadService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startUploadService() {
        val intent = Intent(this, UploadForegroundService::class.java).apply {
            action = UploadForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopUploadService() {
        val intent = Intent(this, UploadForegroundService::class.java).apply {
            action = UploadForegroundService.ACTION_STOP
        }
        startService(intent)
    }
}
