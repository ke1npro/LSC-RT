package com.academic.asl.sign_language_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

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
                        val fps = call.argument<Double>("fps") ?: 20.0
                        val maxDimension = call.argument<Int>("maxDimension") ?: 360
                        val useGpu = call.argument<Boolean>("useGpu") ?: false
                        if (videoPath.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "Ruta de video requerida", null)
                            return@setMethodCallHandler
                        }
                        val replied = AtomicBoolean(false)
                        processor.processVideo(
                            videoPath = videoPath,
                            fpsTarget = fps,
                            maxDimension = maxDimension,
                            useGpu = useGpu,
                            onSuccess = { frames ->
                                if (replied.compareAndSet(false, true)) {
                                    result.success(frames)
                                }
                            },
                            onError = { code, msg ->
                                if (replied.compareAndSet(false, true)) {
                                    result.error(code, msg, null)
                                }
                            }
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
