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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.NonCancellable
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min

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

    private fun scaleBitmapIfNeeded(bitmap: Bitmap, maxDimension: Int): Bitmap {
        if (maxDimension <= 0) return bitmap
        val w = bitmap.width
        val h = bitmap.height
        val largest = max(w, h)
        if (largest <= maxDimension) return bitmap
        val scale = maxDimension.toFloat() / largest.toFloat()
        val targetW = max(1, (w * scale).toInt())
        val targetH = max(1, (h * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(bitmap, targetW, targetH, false)
        if (scaled !== bitmap) {
            bitmap.recycle()
        }
        return scaled
    }

    private fun extractHands(result: HandLandmarkerResult): List<Map<String, Any>> {
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

            val handednessCategory =
                if (hIdx < handednessGroup.size && handednessGroup[hIdx].isNotEmpty()) {
                    handednessGroup[hIdx][0]
                } else {
                    null
                }

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
        return handsList
    }

    fun processVideo(
        videoPath: String,
        fpsTarget: Double = 20.0,
        maxDimension: Int = 360,
        useGpu: Boolean = false,
        onSuccess: (List<Map<String, Any>>) -> Unit,
        onError: (String, String?) -> Unit
    ) {
        val videoFile = File(videoPath)
        if (!videoFile.exists() || videoFile.length() == 0L) {
            onError("FILE_NOT_FOUND", "El archivo de video no existe o está vacío: $videoPath")
            return
        }

        val previousJob = activeJob
        previousJob?.cancel()

        activeJob = scope.launch {
            previousJob?.cancelAndJoin()
            if (!isActive) return@launch

            var landmarker: HandLandmarker? = null
            val retriever = MediaMetadataRetriever()

            try {
                retriever.setDataSource(videoPath)

                val durationStr =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull() ?: 0L
                if (durationMs <= 0L) {
                    withContext(Dispatchers.Main) {
                        onError("INVALID_VIDEO", "No se pudo leer la duración del video")
                    }
                    return@launch
                }

                val frameCountStr =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
                val reportedFrameCount = frameCountStr?.toIntOrNull() ?: 0

                val measuredSourceFps = if (reportedFrameCount > 0 && durationMs > 0) {
                    (reportedFrameCount.toDouble() * 1000.0) / durationMs.toDouble()
                } else {
                    30.0
                }
                val sourceFps = if (measuredSourceFps in 5.0..120.0) measuredSourceFps else 30.0

                val totalSourceFrames = if (reportedFrameCount > 0) {
                    reportedFrameCount
                } else {
                    max(1, ((durationMs / 1000.0) * sourceFps).toInt())
                }

                val effectiveTargetFps = fpsTarget.coerceIn(10.0, sourceFps)
                val stride = (sourceFps / effectiveTargetFps).coerceAtLeast(1.0)

                val targetSourceIndices = ArrayList<Int>()
                var cursor = 0.0
                while (cursor.toInt() < totalSourceFrames) {
                    val idx = cursor.toInt()
                    if (targetSourceIndices.isEmpty() || targetSourceIndices.last() != idx) {
                        targetSourceIndices.add(idx)
                    }
                    cursor += stride
                }
                if (targetSourceIndices.isEmpty()) {
                    targetSourceIndices.add(0)
                }

                val totalTargetFrames = targetSourceIndices.size
                val targetIndexToOutputPos = HashMap<Int, Int>(totalTargetFrames)
                for (pos in targetSourceIndices.indices) {
                    targetIndexToOutputPos[targetSourceIndices[pos]] = pos
                }

                landmarker = buildLandmarker(useGpu = useGpu)
                val frameResults = ArrayList<Map<String, Any>>(totalTargetFrames)
                val progressInterval = if (totalTargetFrames <= 60) 1 else 2

                var lastTimestampMs = -1L
                fun nextSafeTimestampMs(sourceIdx: Int): Long {
                    val rawTs = ((sourceIdx.toDouble() / sourceFps) * 1000.0).toLong()
                    val safeTs = if (rawTs <= lastTimestampMs) lastTimestampMs + 1 else rawTs
                    lastTimestampMs = safeTs
                    return safeTs
                }

                fun processDecodedBitmap(
                    rawBitmap: Bitmap?,
                    sourceIdx: Int,
                    outputIdx: Int
                ) {
                    val timestampMs = nextSafeTimestampMs(sourceIdx)
                    if (rawBitmap == null) {
                        frameResults.add(
                            mapOf(
                                "frameIndex" to outputIdx,
                                "timestampMs" to timestampMs,
                                "hands" to emptyList<Map<String, Any>>()
                            )
                        )
                    } else {
                        var scaled: Bitmap? = null
                        try {
                            scaled = scaleBitmapIfNeeded(rawBitmap, maxDimension)
                            val mpImage: MPImage = BitmapImageBuilder(scaled).build()
                            val result: HandLandmarkerResult =
                                landmarker.detectForVideo(mpImage, timestampMs)
                            frameResults.add(
                                mapOf(
                                    "frameIndex" to outputIdx,
                                    "timestampMs" to timestampMs,
                                    "hands" to extractHands(result)
                                )
                            )
                        } finally {
                            try {
                                scaled?.recycle()
                            } catch (_: Throwable) {}
                            try {
                                if (!rawBitmap.isRecycled) rawBitmap.recycle()
                            } catch (_: Throwable) {}
                        }
                    }

                    val completed = outputIdx + 1
                    if (completed == totalTargetFrames || completed % progressInterval == 0) {
                        val pct = (completed.toDouble() / totalTargetFrames.toDouble()) * 100.0
                        postProgress(completed, totalTargetFrames, pct)
                    }
                }

                val canUseBatchedDecode =
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && reportedFrameCount > 0

                if (canUseBatchedDecode) {
                    val batchSize = 15
                    val bitmapParams = MediaMetadataRetriever.BitmapParams().apply {
                        preferredConfig = Bitmap.Config.ARGB_8888
                    }
                    var batchStart = 0
                    while (batchStart < totalSourceFrames) {
                        if (!isActive) return@launch
                        val batchEnd = min(totalSourceFrames, batchStart + batchSize)
                        val count = batchEnd - batchStart

                        var hasTargetInBatch = false
                        for (srcIdx in batchStart until batchEnd) {
                            if (targetIndexToOutputPos.containsKey(srcIdx)) {
                                hasTargetInBatch = true
                                break
                            }
                        }
                        if (!hasTargetInBatch) {
                            batchStart = batchEnd
                            continue
                        }

                        val batchBitmaps: List<Bitmap>? = try {
                            retriever.getFramesAtIndex(batchStart, count, bitmapParams)
                        } catch (t: Throwable) {
                            Log.w(TAG, "getFramesAtIndex fallback at $batchStart: ${t.message}")
                            null
                        }

                        if (batchBitmaps != null && batchBitmaps.isNotEmpty()) {
                            for (offset in batchBitmaps.indices) {
                                val srcIdx = batchStart + offset
                                val bmp = batchBitmaps[offset]
                                val outputIdx = targetIndexToOutputPos[srcIdx]
                                if (!isActive || outputIdx == null) {
                                    try {
                                        if (!bmp.isRecycled) bmp.recycle()
                                    } catch (_: Throwable) {}
                                    continue
                                }
                                processDecodedBitmap(bmp, srcIdx, outputIdx)
                            }
                            if (batchBitmaps.size < count) {
                                for (srcIdx in (batchStart + batchBitmaps.size) until batchEnd) {
                                    if (!isActive) return@launch
                                    val outputIdx = targetIndexToOutputPos[srcIdx] ?: continue
                                    val frameTimeUs = ((srcIdx.toDouble() / sourceFps) * 1_000_000.0).toLong()
                                    val bmp = retriever.getFrameAtTime(
                                        frameTimeUs,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    )
                                    processDecodedBitmap(bmp, srcIdx, outputIdx)
                                }
                            }
                        } else {
                            for (srcIdx in batchStart until batchEnd) {
                                if (!isActive) return@launch
                                val outputIdx = targetIndexToOutputPos[srcIdx] ?: continue
                                var bmp: Bitmap? = null
                                try {
                                    bmp = retriever.getFrameAtIndex(srcIdx, bitmapParams)
                                } catch (_: Throwable) {}
                                if (bmp == null) {
                                    val frameTimeUs =
                                        ((srcIdx.toDouble() / sourceFps) * 1_000_000.0).toLong()
                                    bmp = retriever.getFrameAtTime(
                                        frameTimeUs,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    )
                                }
                                processDecodedBitmap(bmp, srcIdx, outputIdx)
                            }
                        }
                        batchStart = batchEnd
                    }
                } else {
                    for (outputIdx in targetSourceIndices.indices) {
                        if (!isActive) return@launch
                        val srcIdx = targetSourceIndices[outputIdx]
                        val frameTimeUs = ((srcIdx.toDouble() / sourceFps) * 1_000_000.0).toLong()
                        val bmp = retriever.getFrameAtTime(
                            frameTimeUs,
                            MediaMetadataRetriever.OPTION_CLOSEST
                        )
                        processDecodedBitmap(bmp, srcIdx, outputIdx)
                    }
                }

                if (!isActive) return@launch
                withContext(Dispatchers.Main) {
                    onSuccess(frameResults)
                }
            } catch (e: CancellationException) {
                withContext(Dispatchers.Main + NonCancellable) {
                    onError("CANCELLED", "Procesamiento reiniciado")
                }
                throw e
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
