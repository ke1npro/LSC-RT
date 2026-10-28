// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/entities/landmark_point.dart';
import 'vision_datasource.dart';

class PlatformVisionDataSource implements VisionDataSource {
  final _handController = StreamController<List<HandPose>>.broadcast();
  final _faceController = StreamController<List<FaceBounds>>.broadcast();
  StreamSubscription? _handSub;
  StreamSubscription? _faceSub;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Stream<List<HandPose>> get handStream => _handController.stream;

  @override
  Stream<List<FaceBounds>> get faceStream => _faceController.stream;

  @override
  Future<void> initialize() async {
    _handSub = html.window.on['flutter_hand_landmarks'].listen((event) {
      if (event is html.CustomEvent && event.detail != null) {
        try {
          final data = jsonDecode(event.detail.toString()) as List<dynamic>;
          final List<HandPose> hands = [];
          for (final handJson in data) {
            final lmList = (handJson as List<dynamic>).map((pt) {
              final map = pt as Map<String, dynamic>;
              return LandmarkPoint(
                x: (map['x'] as num).toDouble(),
                y: (map['y'] as num).toDouble(),
                z: map['z'] != null ? (map['z'] as num).toDouble() : 0.0,
              );
            }).toList();
            hands.add(HandPose(landmarks: lmList, confidence: 1.0));
          }
          _handController.add(hands);
        } catch (_) {}
      }
    });

    _faceSub = html.window.on['flutter_face_boxes'].listen((event) {
      if (event is html.CustomEvent && event.detail != null) {
        try {
          final data = jsonDecode(event.detail.toString()) as List<dynamic>;
          final List<FaceBounds> boundsList = [];
          for (final box in data) {
            final map = box as Map<String, dynamic>;
            boundsList.add(FaceBounds(
              left: (map['x'] as num).toDouble(),
              top: (map['y'] as num).toDouble(),
              width: (map['width'] as num).toDouble(),
              height: (map['height'] as num).toDouble(),
            ));
          }
          _faceController.add(boundsList);
        } catch (_) {}
      }
    });

    _initialized = true;
  }

  @override
  void processFrame(dynamic image, int sensorOrientation) {}

  @override
  void setRotation(int degrees) {}

  @override
  void setFaceDetectionEnabled(bool enabled) {}

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _handSub?.cancel();
    await _faceSub?.cancel();
    await _handController.close();
    await _faceController.close();
  }
}

VisionDataSource createVisionDataSource() => PlatformVisionDataSource();
