package com.academic.asl.sign_language_app

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import io.flutter.FlutterInjector
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

class VideoLandmarkerProcessor(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        private const val TAG = "VideoLandmarker"
        const val METHOD_CHANNEL = "com.academic.asl.sign_language_app/video_landmarker"
        const val EVENT_CHANNEL = "com.academic.asl.sign_language_app/video_landmarker_progress"
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Default + Job())
    private var activeJob: Job? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        activeJob?.cancel()
    }

    private fun postProgress(current: Int, total: Int, percent: Double) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "current" to current,
                    "total" to total,
                    "percent" to percent
                )
            )
        }
    }

    private fun resolveModelPath(): String {
        val candidates = listOf(
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/hand_landmarker.task"),
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("packages/hand_landmarker/assets/hand_landmarker.task"),
            "flutter_assets/assets/hand_landmarker.task",
            "flutter_assets/packages/hand_landmarker/assets/hand_landmarker.task",
            "hand_landmarker.task"
        )

        for (candidate in candidates) {
            try {
                context.assets.open(candidate).use {
                    return candidate
                }
            } catch (_: Exception) {}
        }

        // Si no se encuentra como path relativo de asset directo, intentar copiar a cache
        for (candidate in candidates) {
            try {
                context.assets.open(candidate).use { input ->
                    val outFile = File(context.cacheDir, "hand_landmarker.task")
                    FileOutputStream(outFile).use { output ->
                        input.copyTo(output)
                    }
                    return outFile.absolutePath
                }
            } catch (_: Exception) {}
        }

        return "hand_landmarker.task"
    }

    private fun buildLandmarker(useGpu: Boolean = true): HandLandmarker {
        val modelPath = resolveModelPath()
        val delegate = if (useGpu) Delegate.GPU else Delegate.CPU

        return try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(modelPath)
                .setDelegate(delegate)
                .build()

            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.VIDEO)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.40f)
                .setMinHandPresenceConfidence(0.40f)
                .setMinTrackingConfidence(0.40f)
                .build()

            HandLandmarker.createFromOptions(context, options)
        } catch (e: Exception) {
            Log.w(TAG, "Fallo al inicializar con GPU delegate, fallback a CPU: ${e.message}")
            val baseOptionsCpu = BaseOptions.builder()
                .setModelAssetPath(modelPath)
                .setDelegate(Delegate.CPU)
                .build()

            val optionsCpu = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptionsCpu)
                .setRunningMode(RunningMode.VIDEO)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.40f)
                .setMinHandPresenceConfidence(0.40f)
                .setMinTrackingConfidence(0.40f)
                .build()

            HandLandmarker.createFromOptions(context, optionsCpu)
        }
    }

    fun processVideo(
        videoPath: String,
        fpsTarget: Double = 30.0,
        onSuccess: (List<Map<String, Any>>) -> Unit,
        onError: (String, String?) -> Unit
    ) {
        val videoFile = File(videoPath)
        if (!videoFile.exists() || videoFile.length() == 0L) {
            onError("FILE_NOT_FOUND", "El archivo de video no existe o está vacío: $videoPath")
            return
        }

        activeJob?.cancel()
        activeJob = scope.launch {
            var landmarker: HandLandmarker? = null
            val retriever = MediaMetadataRetriever()

            try {
                retriever.setDataSource(videoPath)

                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull() ?: 0L
                if (durationMs <= 0L) {
                    withContext(Dispatchers.Main) {
                        onError("INVALID_VIDEO", "No se pudo leer la duración del video")
                    }
                    return@launch
                }

                val frameCountStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
                var reportedFrameCount = frameCountStr?.toIntOrNull() ?: 0

                val effectiveFps = if (reportedFrameCount > 0 && durationMs > 0) {
                    (reportedFrameCount.toDouble() * 1000.0) / durationMs.toDouble()
                } else {
                    fpsTarget
                }

                val totalFrames = if (reportedFrameCount > 0) {
                    reportedFrameCount
                } else {
                    max(1, ((durationMs / 1000.0) * effectiveFps).toInt())
                }

                landmarker = buildLandmarker(useGpu = true)
                val frameResults = ArrayList<Map<String, Any>>(totalFrames)
                val frameDurationUs = (1_000_000.0 / effectiveFps).toLong()

                for (frameIdx in 0 until totalFrames) {
                    val frameTimeUs = frameIdx * frameDurationUs
                    val timestampMs = (frameIdx * (1000.0 / effectiveFps)).toLong()

                    var bitmap: Bitmap? = null

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        try {
                            bitmap = retriever.getFrameAtIndex(frameIdx)
                        } catch (_: Throwable) {}
                    }

                    if (bitmap == null) {
                        bitmap = retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    }

                    if (bitmap == null) {
                        // Frame no recuperado, registrar frame vacío
                        frameResults.add(
                            mapOf(
                                "frameIndex" to frameIdx,
                                "timestampMs" to timestampMs,
                                "hands" to emptyList<Map<String, Any>>()
                            )
                        )
                        val pct = ((frameIdx + 1).toDouble() / totalFrames.toDouble()) * 100.0
                        postProgress(frameIdx + 1, totalFrames, pct)
                        continue
                    }

                    val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                    val result: HandLandmarkerResult = landmarker.detectForVideo(mpImage, timestampMs)

                    val handsList = ArrayList<Map<String, Any>>()
                    val landmarksGroup = result.landmarks()
                    val handednessGroup = result.handednesses()

                    for (hIdx in landmarksGroup.indices) {
                        val handLandmarks = landmarksGroup[hIdx]
                        val landmarkPoints = ArrayList<Map<String, Double>>(handLandmarks.size)
                        for (pt in handLandmarks) {
                            landmarkPoints.add(
                                mapOf(
                                    "x" to pt.x().toDouble(),
                                    "y" to pt.y().toDouble(),
                                    "z" to pt.z().toDouble()
                                )
                            )
                        }

                        val handednessCategory = if (hIdx < handednessGroup.size && handednessGroup[hIdx].isNotEmpty()) {
                            handednessGroup[hIdx][0]
                        } else null

                        val label = handednessCategory?.categoryName() ?: "Unknown"
                        val confidence = handednessCategory?.score()?.toDouble() ?: 0.85

                        handsList.add(
                            mapOf(
                                "handedness" to label,
                                "confidence" to confidence,
                                "landmarks" to landmarkPoints
                            )
                        )
                    }

                    frameResults.add(
                        mapOf(
                            "frameIndex" to frameIdx,
                            "timestampMs" to timestampMs,
                            "hands" to handsList
                        )
                    )

                    // Liberación inmediata de memoria para evitar OOM
                    bitmap.recycle()

                    val pct = ((frameIdx + 1).toDouble() / totalFrames.toDouble()) * 100.0
                    postProgress(frameIdx + 1, totalFrames, pct)
                }

                withContext(Dispatchers.Main) {
                    onSuccess(frameResults)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error durante procesamiento de video", e)
                withContext(Dispatchers.Main) {
                    onError("PROCESSING_ERROR", e.message ?: "Error desconocido al procesar video")
                }
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {}
                try {
                    landmarker?.close()
                } catch (_: Throwable) {}
            }
        }
    }
}
