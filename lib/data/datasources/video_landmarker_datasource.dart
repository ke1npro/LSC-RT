import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/entities/landmark_point.dart';
import '../../domain/entities/recorded_sign.dart';

class VideoProgressUpdate {
  final int currentFrame;
  final int totalFrames;
  final double percent;

  const VideoProgressUpdate({
    required this.currentFrame,
    required this.totalFrames,
    required this.percent,
  });
}

class VideoLandmarkerDataSource {
  static const MethodChannel _methodChannel =
      MethodChannel('com.academic.asl.sign_language_app/video_landmarker');
  static const EventChannel _eventChannel =
      EventChannel('com.academic.asl.sign_language_app/video_landmarker_progress');

  Stream<VideoProgressUpdate>? _progressStream;

  Stream<VideoProgressUpdate> get progressStream {
    _progressStream ??= _eventChannel
        .receiveBroadcastStream()
        .map<VideoProgressUpdate>((dynamic event) {
      if (event is Map) {
        final current = (event['current'] as num?)?.toInt() ?? 0;
        final total = (event['total'] as num?)?.toInt() ?? 0;
        final percent = (event['percent'] as num?)?.toDouble() ?? 0.0;
        return VideoProgressUpdate(
          currentFrame: current,
          totalFrames: total,
          percent: percent,
        );
      }
      return const VideoProgressUpdate(currentFrame: 0, totalFrames: 0, percent: 0.0);
    });
    return _progressStream!;
  }

  /// Procesa un archivo de video local offline con MediaPipe HandLandmarker (RunningMode.VIDEO).
  Future<List<SignFrameLandmarks>> processVideo({
    required String videoPath,
    double fps = 30.0,
  }) async {
    try {
      final dynamic raw = await _methodChannel.invokeMethod('processVideo', {
        'videoPath': videoPath,
        'fps': fps,
      });

      if (raw is! List) {
        return const [];
      }

      final List<SignFrameLandmarks> frames = [];
      for (final item in raw) {
        if (item is! Map) continue;
        final frameIndex = (item['frameIndex'] as num?)?.toInt() ?? 0;
        final timestampMs = (item['timestampMs'] as num?)?.toInt() ?? 0;
        final rawHands = item['hands'];

        final List<HandPose> hands = [];
        if (rawHands is List) {
          for (final h in rawHands) {
            if (h is! Map) continue;
            final handedness = h['handedness'] as String?;
            final confidence = (h['confidence'] as num?)?.toDouble() ?? 1.0;
            final rawPoints = h['landmarks'];

            final List<LandmarkPoint> points = [];
            if (rawPoints is List) {
              for (final p in rawPoints) {
                if (p is! Map) continue;
                points.add(
                  LandmarkPoint(
                    x: (p['x'] as num?)?.toDouble() ?? 0.0,
                    y: (p['y'] as num?)?.toDouble() ?? 0.0,
                    z: (p['z'] as num?)?.toDouble() ?? 0.0,
                  ),
                );
              }
            }

            hands.add(
              HandPose(
                landmarks: points,
                confidence: confidence,
                handedness: handedness,
              ),
            );
          }
        }

        frames.add(
          SignFrameLandmarks(
            frameIndex: frameIndex,
            timestampMs: timestampMs,
            hands: hands,
          ),
        );
      }

      return frames;
    } on PlatformException catch (e) {
      AppLogger.e('VideoLandmarkerDataSource: Error de plataforma al procesar video', e);
      rethrow;
    } catch (e) {
      AppLogger.e('VideoLandmarkerDataSource: Error inesperado', e);
      rethrow;
    }
  }
}
