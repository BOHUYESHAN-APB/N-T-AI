package com.bohuyeshan.ntai.floating

import android.app.Service
import android.content.Context
import android.content.Intent
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

        fun startService(context: Context, modelPath: String) {
            val intent = Intent(context, FloatingWindowService::class.java)
            intent.putExtra("modelPath", modelPath)
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
    }

    private var windowManager: WindowManager? = null
    private var floatingView: FrameLayout? = null
    private var webView: WebView? = null
    private var webViewClient: FloatingWebViewClient? = null
    private var isInitialized = false

    private var lastX = 0
    private var lastY = 0
    private var lastTouchX = 0f
    private var lastTouchY = 0f

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "FloatingWindowService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "FloatingWindowService started")

        val modelPath = intent?.getStringExtra("modelPath") ?: ""
        
        // 创建浮窗
        createFloatingWindow(modelPath)

        return START_STICKY
    }

    private fun createFloatingWindow(modelPath: String) {
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
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = 600
            height = 800
            x = 100
            y = 100
            gravity = Gravity.TOP or Gravity.LEFT
        }

        // 添加浮窗视图
        windowManager?.addView(floatingView, params)

        // 加载 Web 页面
        val url = "http://localhost:8000/static/live2d/index.html?model=$modelPath&floating=true"
        webView?.loadUrl(url)

        // 设置触摸事件
        floatingView?.setOnTouchListener { view, event ->
            handleTouchEvent(view, event, params)
            false
        }

        isInitialized = true
        Log.d(TAG, "Floating window created successfully")
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
