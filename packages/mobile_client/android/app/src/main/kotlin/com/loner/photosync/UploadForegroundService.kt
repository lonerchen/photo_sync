package com.loner.photosync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class UploadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "photo_upload_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_UPLOAD"
        const val ACTION_STOP = "STOP_UPLOAD"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification("正在上传照片...")
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "照片上传",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台上传照片到存储服务器"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PhotoSync 照片搬家")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
