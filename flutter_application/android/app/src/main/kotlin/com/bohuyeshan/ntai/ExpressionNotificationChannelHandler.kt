package com.bohuyeshan.ntai

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ExpressionNotificationChannelHandler(private val activity: Activity) {
    companion object {
        private const val CHANNEL = "com.bohuyeshan.ntai/notification"
        private const val TAG = "ExpressionNotification"
        private const val NOTIFICATION_ID = 2001
        private const val CHANNEL_ID = "expression_status"
        private const val PERMISSION_REQUEST_CODE = 2025
    }

    fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initExpressionNotification" -> handleInit(result)
                    "updateExpressionNotification" -> handleUpdate(call, result)
                    "clearExpressionNotification" -> handleClear(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInit(result: MethodChannel.Result) {
        try {
            ensureNotificationPermission()
            ensureChannel()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Init error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleUpdate(call: MethodCall, result: MethodChannel.Result) {
        try {
            ensureChannel()
            val title = call.argument<String>("title") ?: "N-T-AI"
            val content = call.argument<String>("content") ?: ""
            val face = call.argument<String>("face") ?: ""

            val launchIntent = activity.packageManager.getLaunchIntentForPackage(activity.packageName)
            val pendingIntent = if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                } else {
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
                }
                android.app.PendingIntent.getActivity(activity, 0, launchIntent, flags)
            } else {
                null
            }

            val builder = NotificationCompat.Builder(activity, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(content)
                .setSubText(face)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)

            if (pendingIntent != null) {
                builder.setContentIntent(pendingIntent)
            }

            val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, builder.build())
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Update error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleClear(result: MethodChannel.Result) {
        try {
            val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Clear error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Expression Status",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "Shows current expression status"
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST_CODE
            )
        }
    }
}
