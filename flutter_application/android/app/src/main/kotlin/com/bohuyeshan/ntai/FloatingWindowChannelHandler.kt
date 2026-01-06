package com.bohuyeshan.ntai

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import android.util.Log
import com.bohuyeshan.ntai.floating.FloatingWindowService

class FloatingWindowChannelHandler(private val activity: Activity) {
    companion object {
        private const val CHANNEL = "com.bohuyeshan.ntai/floating_window"
        private const val TAG = "FloatingWindowHandler"
        private const val PERMISSION_REQUEST_CODE = 2024
    }

    private data class PendingCreateRequest(
        val modelPath: String,
        val width: Double,
        val height: Double,
        val showControls: Boolean
    )

    private var pendingCreateRequest: PendingCreateRequest? = null
    private var backendUrl: String = "http://localhost:23456"

    fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> handleInitialize(call, result)
                    "updateBackendUrl" -> handleUpdateBackendUrl(call, result)
                    "createFloatingWindow" -> handleCreateFloatingWindow(call, result)
                    "showFloatingWindow" -> handleShowFloatingWindow(call, result)
                    "hideFloatingWindow" -> handleHideFloatingWindow(call, result)
                    "closeFloatingWindow" -> handleCloseFloatingWindow(call, result)
                    "isFloatingWindowVisible" -> handleIsFloatingWindowVisible(call, result)
                    "setPosition" -> handleSetPosition(call, result)
                    "setSize" -> handleSetSize(call, result)
                    "setAlwaysOnTop" -> handleSetAlwaysOnTop(call, result)
                    "executeJavaScript" -> handleExecuteJavaScript(call, result)
                    "dispose" -> handleDispose(call, result)
                    "hasPermission" -> handleHasPermission(call, result)
                    "requestPermission" -> handleRequestPermission(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInitialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Initialize called")
            // Accept backendUrl from Flutter side for WebView content
            val provided = call.argument<String>("backendUrl")
            if (provided != null && provided.isNotEmpty()) {
                backendUrl = provided
                Log.d(TAG, "Backend URL set to $backendUrl")
            }
            // 检查是否需要权限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(activity)) {
                    Log.w(TAG, "SYSTEM_ALERT_WINDOW permission not available")
                    result.error("PERMISSION_ERROR", "Missing SYSTEM_ALERT_WINDOW permission", null)
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Initialize error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCreateFloatingWindow(call: MethodCall, result: MethodChannel.Result) {
        try {
            val modelPath = call.argument<String>("modelPath") ?: ""
            val width = call.argument<Double>("width") ?: 600.0
            val height = call.argument<Double>("height") ?: 800.0
            val showControls = call.argument<Boolean>("showControls") ?: false

            Log.d(TAG, "Create floating window: model=$modelPath, ${width}x$height, controls=$showControls")

            // 请求权限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(activity)) {
                    pendingCreateRequest = PendingCreateRequest(
                        modelPath = modelPath,
                        width = width,
                        height = height,
                        showControls = showControls
                    )
                    requestOverlayPermission()
                    result.error("PERMISSION_REQUIRED", "Need SYSTEM_ALERT_WINDOW permission", null)
                    return
                }
            }

            // 启动浮窗服务，并传入 backendUrl
            FloatingWindowService.startService(activity, modelPath, backendUrl, showControls, width, height)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Create floating window error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleUpdateBackendUrl(call: MethodCall, result: MethodChannel.Result) {
        try {
            val provided = call.argument<String>("backendUrl")
            if (provided != null && provided.isNotEmpty()) {
                backendUrl = provided
                Log.d(TAG, "Backend URL updated to $backendUrl")
                FloatingWindowService.updateBackendUrl(backendUrl)
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Update backend URL error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleShowFloatingWindow(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Show floating window")
            FloatingWindowService.show()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Show floating window error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleHideFloatingWindow(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Hide floating window")
            FloatingWindowService.hide()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Hide floating window error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCloseFloatingWindow(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Close floating window")
            FloatingWindowService.stopService(activity)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Close floating window error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleIsFloatingWindowVisible(call: MethodCall, result: MethodChannel.Result) {
        try {
            result.success(FloatingWindowService.isVisible())
        } catch (e: Exception) {
            Log.e(TAG, "Is visible error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSetPosition(call: MethodCall, result: MethodChannel.Result) {
        try {
            val x = call.argument<Double>("x") ?: 0.0
            val y = call.argument<Double>("y") ?: 0.0
            Log.d(TAG, "Set position: x=$x, y=$y")
            FloatingWindowService.setPosition(x.toInt(), y.toInt())
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Set position error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSetSize(call: MethodCall, result: MethodChannel.Result) {
        try {
            val width = call.argument<Double>("width") ?: 600.0
            val height = call.argument<Double>("height") ?: 800.0
            Log.d(TAG, "Set size: ${width}x$height")
            FloatingWindowService.setSize(width.toInt(), height.toInt())
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Set size error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSetAlwaysOnTop(call: MethodCall, result: MethodChannel.Result) {
        try {
            val alwaysOnTop = call.argument<Boolean>("alwaysOnTop") ?: false
            Log.d(TAG, "Set always on top: $alwaysOnTop")
            FloatingWindowService.setAlwaysOnTop(alwaysOnTop)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Set always on top error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleExecuteJavaScript(call: MethodCall, result: MethodChannel.Result) {
        try {
            val code = call.argument<String>("code") ?: ""
            Log.d(TAG, "Execute JavaScript")
            FloatingWindowService.executeJavaScript(code)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Execute JS error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleDispose(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Dispose")
            FloatingWindowService.stopService(activity)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Dispose error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleHasPermission(call: MethodCall, result: MethodChannel.Result) {
        try {
            val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(activity)
            } else {
                true // Android M 以下默认有权限
            }
            Log.d(TAG, "Has permission: $hasPermission")
            result.success(hasPermission)
        } catch (e: Exception) {
            Log.e(TAG, "Has permission error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleRequestPermission(call: MethodCall, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Request permission")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(activity)) {
                    requestOverlayPermission()
                    result.success(false) // 权限请求已发送，等待用户响应
                    return
                }
            }
            result.success(true) // 已有权限
        } catch (e: Exception) {
            Log.e(TAG, "Request permission error", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")
            )
            activity.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            Log.d(TAG, "Permission result: $resultCode")
            // 权限请求完成后的处理
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(activity)) {
                    return
                }
            }

            val pending = pendingCreateRequest ?: return
            pendingCreateRequest = null
            FloatingWindowService.startService(
                activity,
                pending.modelPath,
                backendUrl,
                pending.showControls,
                pending.width,
                pending.height
            )
        }
    }
}
