package com.example.flutter_application

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.bohuyeshan.ntai.FloatingWindowChannelHandler
import com.bohuyeshan.ntai.ExpressionNotificationChannelHandler

class MainActivity : FlutterActivity() {
    private lateinit var floatingWindowHandler: FloatingWindowChannelHandler
    private lateinit var expressionNotificationHandler: ExpressionNotificationChannelHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 设置浮窗窗口 MethodChannel
        floatingWindowHandler = FloatingWindowChannelHandler(this)
        floatingWindowHandler.setupChannel(flutterEngine)

        // 表情通知栏 MethodChannel
        expressionNotificationHandler = ExpressionNotificationChannelHandler(this)
        expressionNotificationHandler.setupChannel(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        floatingWindowHandler.onActivityResult(requestCode, resultCode, data)
    }
}
