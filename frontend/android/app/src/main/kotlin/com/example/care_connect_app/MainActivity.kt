package com.example.care_connect_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OcrHandler.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MediaPipeLlmHandler.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
