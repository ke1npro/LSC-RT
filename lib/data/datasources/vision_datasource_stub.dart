import 'dart:async';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import 'vision_datasource.dart';

class PlatformVisionDataSource implements VisionDataSource {
  final _handController = StreamController<List<HandPose>>.broadcast();
  final _faceController = StreamController<List<FaceBounds>>.broadcast();

  @override
  bool get isInitialized => true;

  @override
  Stream<List<HandPose>> get handStream => _handController.stream;

  @override
  Stream<List<FaceBounds>> get faceStream => _faceController.stream;

  @override
  Future<void> initialize() async {}

  @override
  void processFrame(dynamic image, int sensorOrientation) {}

  @override
  Future<void> dispose() async {
    await _handController.close();
    await _faceController.close();
  }
}

VisionDataSource createVisionDataSource() => PlatformVisionDataSource();
