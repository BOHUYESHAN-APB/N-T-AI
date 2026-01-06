package com.bohuyeshan.ntai.floating

import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.util.Log

class FloatingWindowService : Service() {

    companion object {
        private const val TAG = "FloatingWindowService"
        private const val NOTIFICATION_ID = 1001
        private var activeInstance: FloatingWindowService? = null

        fun startService(
            context: Context,
            modelPath: String,
            backendUrl: String,
            showControls: Boolean,
            width: Double,
            height: Double
        ) {
            val intent = Intent(context, FloatingWindowService::class.java)
            intent.putExtra("modelPath", modelPath)
            intent.putExtra("backendUrl", backendUrl)
            intent.putExtra("showControls", showControls)
            intent.putExtra("windowWidth", width)
            intent.putExtra("windowHeight", height)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, FloatingWindowService::class.java)
            context.stopService(intent)
        }

        fun show(): Boolean {
            return activeInstance?.setWindowVisible(true) ?: false
        }

        fun hide(): Boolean {
            return activeInstance?.setWindowVisible(false) ?: false
        }

        fun isVisible(): Boolean {
            return activeInstance?.isWindowVisible() ?: false
        }

        fun setPosition(x: Int, y: Int): Boolean {
            return activeInstance?.updatePosition(x, y) ?: false
        }

        fun setSize(width: Int, height: Int): Boolean {
            return activeInstance?.updateSize(width, height) ?: false
        }

        fun setAlwaysOnTop(alwaysOnTop: Boolean): Boolean {
            return activeInstance?.updateAlwaysOnTop(alwaysOnTop) ?: false
        }

        fun updateBackendUrl(backendUrl: String): Boolean {
            return activeInstance?.reloadBackendUrl(backendUrl) ?: false
        }

        fun executeJavaScript(code: String): Boolean {
            return activeInstance?.runJavaScript(code) ?: false
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: FrameLayout? = null
    private var webView: WebView? = null
    private var webViewClient: FloatingWebViewClient? = null
    private var isInitialized = false
    private var windowParams: WindowManager.LayoutParams? = null
    private var currentModelPath: String = ""
    private var currentBackendUrl: String = ""
    private var currentShowControls: Boolean = false

    private var lastX = 0
    private var lastY = 0
    private var lastTouchX = 0f
    private var lastTouchY = 0f

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "FloatingWindowService created")
        activeInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "FloatingWindowService started")

        val modelPath = intent?.getStringExtra("modelPath") ?: ""
        val backendUrl = intent?.getStringExtra("backendUrl") ?: "http://localhost:23456"
        val showControls = intent?.getBooleanExtra("showControls", false) ?: false
        val windowWidth = intent?.getDoubleExtra("windowWidth", 600.0) ?: 600.0
        val windowHeight = intent?.getDoubleExtra("windowHeight", 800.0) ?: 800.0

        // 创建浮窗
        createFloatingWindow(modelPath, backendUrl, showControls, windowWidth, windowHeight)

        return START_STICKY
    }

    private fun createFloatingWindow(
        modelPath: String,
        backendUrl: String,
        showControls: Boolean,
        windowWidth: Double,
        windowHeight: Double
    ) {
        if (isInitialized) return

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // 检查权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                Log.w(TAG, "SYSTEM_ALERT_WINDOW permission not granted")
                stopSelf()
                return
            }
        }

        // 启动前台服务通知 (Android 8.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "floating_window_channel"
            val channelName = "Floating Window Service"
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_LOW)
            channel.lightColor = Color.BLUE
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)

            val notification = Notification.Builder(this, channelId)
                .setContentTitle("N-T-AI Floating Window")
                .setContentText("Running...")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .build()

            startForeground(NOTIFICATION_ID, notification)
        }

        // 创建容器 FrameLayout
        floatingView = FrameLayout(this)
        floatingView?.setBackgroundColor(0x00000000) // 透明背景

        // 创建 WebView
        webView = WebView(this).apply {
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            }
            setBackgroundColor(0x00000000)
            webViewClient = FloatingWebViewClient()
        }

        floatingView?.addView(
            webView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        // 设置窗口参数
        val params = WindowManager.LayoutParams().apply {
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
            }
            format = PixelFormat.RGBA_8888
            // Removed FLAG_NOT_TOUCHABLE to allow touch events
            flags = WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = windowWidth.toInt()
            height = windowHeight.toInt()
            x = 100
            y = 100
            gravity = Gravity.TOP or Gravity.LEFT
        }

        // 添加浮窗视图
        windowManager?.addView(floatingView, params)
        windowParams = params

        // 加载 Web 页面
        val base = backendUrl.trimEnd('/')
        currentBackendUrl = base
        currentModelPath = modelPath
        currentShowControls = showControls
        val url = "$base/static/live2d/index.html?model=$modelPath&floating=true&controls=$showControls&capture=flutter"
        webView?.loadUrl(url)

        // 设置触摸事件
        floatingView?.setOnTouchListener { view, event ->
            handleTouchEvent(view, event, params)
            false
        }

        isInitialized = true
        Log.d(TAG, "Floating window created successfully")
    }

    private fun setWindowVisible(visible: Boolean): Boolean {
        val view = floatingView ?: return false
        view.visibility = if (visible) View.VISIBLE else View.GONE
        return true
    }

    private fun isWindowVisible(): Boolean {
        val view = floatingView ?: return false
        return view.visibility == View.VISIBLE
    }

    private fun updatePosition(x: Int, y: Int): Boolean {
        val view = floatingView ?: return false
        val manager = windowManager ?: return false
        val params = windowParams ?: return false
        params.x = x
        params.y = y
        manager.updateViewLayout(view, params)
        return true
    }

    private fun updateSize(width: Int, height: Int): Boolean {
        val view = floatingView ?: return false
        val manager = windowManager ?: return false
        val params = windowParams ?: return false
        params.width = width
        params.height = height
        manager.updateViewLayout(view, params)
        return true
    }

    private fun updateAlwaysOnTop(alwaysOnTop: Boolean): Boolean {
        val view = floatingView ?: return false
        val manager = windowManager ?: return false
        val params = windowParams ?: return false
        params.flags = if (alwaysOnTop) {
            params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        } else {
            params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        manager.updateViewLayout(view, params)
        return true
    }

    private fun reloadBackendUrl(backendUrl: String): Boolean {
        val view = webView ?: return false
        val base = backendUrl.trimEnd('/')
        currentBackendUrl = base
        val url = "$base/static/live2d/index.html?model=$currentModelPath&floating=true&controls=$currentShowControls&capture=flutter"
        view.post { view.loadUrl(url) }
        return true
    }

    private fun runJavaScript(code: String): Boolean {
        val view = webView ?: return false
        view.post { view.evaluateJavascript(code, null) }
        return true
    }

    private fun handleTouchEvent(
        view: View,
        event: MotionEvent,
        params: WindowManager.LayoutParams
    ) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                lastTouchX = event.rawX
                lastTouchY = event.rawY
                lastX = params.x
                lastY = params.y
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = (event.rawX - lastTouchX).toInt()
                val dy = (event.rawY - lastTouchY).toInt()
                params.x = lastX + dx
                params.y = lastY + dy
                windowManager?.updateViewLayout(view, params)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "FloatingWindowService destroyed")
        if (floatingView != null && windowManager != null) {
            try {
                windowManager?.removeView(floatingView)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing floating view", e)
            }
        }
        webView?.destroy()
        activeInstance = null
        isInitialized = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // 简单的 WebViewClient 实现
    private inner class FloatingWebViewClient : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
            return false
        }
    }
}
