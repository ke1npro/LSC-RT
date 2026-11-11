package com.academic.asl.sign_language_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SECURITY_CHANNEL = "com.academic.asl.sign_language_app/security"
    private var videoProcessor: VideoLandmarkerProcessor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Mitigacion M6: FLAG_SECURE bloquea capturas de pantalla y snapshot en app switcher
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal de Seguridad
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    if (enable) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "isSecureFlagActive" -> {
                    val flags = window.attributes.flags
                    val isSecure = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(isSecure)
                }
                else -> result.notImplemented()
            }
        }

        // Canal de Procesamiento de Video Offline con MediaPipe Tasks Vision
        val processor = VideoLandmarkerProcessor(applicationContext)
        videoProcessor = processor

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VideoLandmarkerProcessor.EVENT_CHANNEL)
            .setStreamHandler(processor)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VideoLandmarkerProcessor.METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "processVideo" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val fps = call.argument<Double>("fps") ?: 30.0
                        if (videoPath.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "Ruta de video requerida", null)
                            return@setMethodCallHandler
                        }
                        processor.processVideo(
                            videoPath = videoPath,
                            fpsTarget = fps,
                            onSuccess = { frames ->
                                result.success(frames)
                            },
                            onError = { code, msg ->
                                result.error(code, msg, null)
                            }
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
