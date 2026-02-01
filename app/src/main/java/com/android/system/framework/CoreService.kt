package com.android.system.framework

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class CoreService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "System_Core"
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Framework Service", NotificationManager.IMPORTANCE_MIN)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .build()
        startForeground(1, notification)
        return START_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
