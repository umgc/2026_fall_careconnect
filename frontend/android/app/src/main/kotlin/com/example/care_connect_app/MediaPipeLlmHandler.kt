package com.example.care_connect_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native Android bridge for Google MediaPipe / LiteRT LLM Inference on-device.
 * Executes quantized models (such as Gemma-2B) locally on mobile GPU/CPU.
 */
object MediaPipeLlmHandler : MethodChannel.MethodCallHandler {

    private const val CHANNEL_NAME = "care_connect/mediapipe_llm"
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    private var llmInference: LlmInference? = null
    private var loadedModelPath: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> checkAvailability(result)
            "initialize" -> initializeEngine(call, result)
            "generate" -> generateResponse(call, result)
            "close" -> closeEngine(result)
            else -> result.notImplemented()
        }
    }

    private fun resolveModelPath(customPath: String?): String? {
        if (!customPath.isNullOrBlank()) {
            val customFile = File(customPath)
            if (customFile.exists() && customFile.length() > 0) {
                return customFile.absolutePath
            }
        }

        // Standard model search locations on Android storage
        val candidatePaths = listOf(
            "/sdcard/Download/gemma-2b.bin",
            "/sdcard/Download/gemma-2b-it-gpu-int4.bin",
            "/sdcard/Download/model.bin",
            "${appContext.filesDir.absolutePath}/models/gemma-2b.bin",
            "${appContext.getExternalFilesDir(null)?.absolutePath}/gemma-2b.bin"
        )

        for (candidate in candidatePaths) {
            val file = File(candidate)
            if (file.exists() && file.length() > 0) {
                return file.absolutePath
            }
        }
        return null
    }

    private fun isNativeSupported(): Boolean {
        // MediaPipe Tasks GenAI native runtime is bundled ONLY for arm64-v8a.
        // On x86_64 emulators, Build.SUPPORTED_ABIS may list arm64-v8a via binary translation,
        // but the 64-bit x86 Android process cannot dlopen an arm64 .so without translation in process.
        val primaryAbi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: ""
        if (!primaryAbi.contains("arm64")) {
            return false
        }
        return try {
            System.loadLibrary("llm_inference_engine_jni")
            true
        } catch (t: Throwable) {
            false
        }
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        Thread {
            val supported = isNativeSupported()
            val path = if (supported) resolveModelPath(null) else null
            val isReady = llmInference != null
            val response = mapOf(
                "available" to (supported && (path != null || isReady)),
                "isInitialized" to isReady,
                "modelPath" to (loadedModelPath ?: path ?: ""),
                "suggestedPath" to "/sdcard/Download/gemma-2b.bin",
                "reason" to if (!supported) "MediaPipe LLM requires ARM64 (current: ${android.os.Build.SUPPORTED_ABIS.joinToString()})" else ""
            )
            mainHandler.post { result.success(response) }
        }.start()
    }

    private fun initializeEngine(call: MethodCall, result: MethodChannel.Result) {
        val customPath = call.argument<String>("modelPath")
        val maxTokens = call.argument<Int>("maxTokens") ?: 256
        val topK = call.argument<Int>("topK") ?: 40
        val temperature = (call.argument<Double>("temperature") ?: 0.2).toFloat()

        Thread {
            try {
                if (!isNativeSupported()) {
                    mainHandler.post {
                        result.error(
                            "UNSUPPORTED_ABI",
                            "MediaPipe LLM requires ARM64 hardware (ABI: ${android.os.Build.SUPPORTED_ABIS.joinToString()})",
                            null
                        )
                    }
                    return@Thread
                }

                val resolvedPath = resolveModelPath(customPath)
                if (resolvedPath == null) {
                    mainHandler.post {
                        result.error(
                            "MODEL_NOT_FOUND",
                            "Model file not found. Push Gemma-2B to /sdcard/Download/gemma-2b.bin",
                            null
                        )
                    }
                    return@Thread
                }

                if (llmInference != null && loadedModelPath == resolvedPath) {
                    mainHandler.post {
                        result.success(mapOf("success" to true, "modelPath" to resolvedPath))
                    }
                    return@Thread
                }

                // Close any existing instance
                llmInference?.close()
                llmInference = null

                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(resolvedPath)
                    .setMaxTokens(maxTokens)
                    .setTopK(topK)
                    .setTemperature(temperature)
                    .build()

                llmInference = LlmInference.createFromOptions(appContext, options)
                loadedModelPath = resolvedPath

                mainHandler.post {
                    result.success(mapOf("success" to true, "modelPath" to resolvedPath))
                }
            } catch (e: Throwable) {
                mainHandler.post {
                    result.error("INIT_FAILED", e.message ?: "Failed to initialize native engine", null)
                }
            }
        }.start()
    }

    private fun generateResponse(call: MethodCall, result: MethodChannel.Result) {
        val prompt = call.argument<String>("prompt") ?: ""
        if (prompt.isBlank()) {
            result.error("EMPTY_PROMPT", "Prompt cannot be empty", null)
            return
        }

        Thread {
            try {
                if (!isNativeSupported()) {
                    mainHandler.post {
                        result.error(
                            "UNSUPPORTED_ABI",
                            "MediaPipe LLM requires ARM64 hardware (ABI: ${android.os.Build.SUPPORTED_ABIS.joinToString()})",
                            null
                        )
                    }
                    return@Thread
                }

                val engine = llmInference
                if (engine == null) {
                    // Try auto-initialization if a model is present
                    val autoPath = resolveModelPath(null)
                    if (autoPath != null) {
                        val options = LlmInference.LlmInferenceOptions.builder()
                            .setModelPath(autoPath)
                            .setMaxTokens(256)
                            .setTopK(40)
                            .setTemperature(0.2f)
                            .build()
                        llmInference = LlmInference.createFromOptions(appContext, options)
                        loadedModelPath = autoPath
                    } else {
                        mainHandler.post {
                            result.error(
                                "NOT_INITIALIZED",
                                "MediaPipe LLM is not initialized. Please load model first.",
                                null
                            )
                        }
                        return@Thread
                    }
                }

                val startTime = System.currentTimeMillis()
                val responseText = llmInference?.generateResponse(prompt) ?: ""
                val latencyMs = System.currentTimeMillis() - startTime

                val responseMap = mapOf(
                    "success" to true,
                    "content" to responseText,
                    "model" to "gemma-2b-mediapipe",
                    "latencyMs" to latencyMs
                )
                mainHandler.post { result.success(responseMap) }
            } catch (e: Throwable) {
                mainHandler.post {
                    result.error("INFERENCE_ERROR", e.message ?: "Native inference error", null)
                }
            }
        }.start()
    }

    private fun closeEngine(result: MethodChannel.Result) {
        try {
            llmInference?.close()
            llmInference = null
            loadedModelPath = null
            result.success(true)
        } catch (e: Throwable) {
            result.error("CLOSE_ERROR", e.message ?: "Failed to close engine", null)
        }
    }
}
