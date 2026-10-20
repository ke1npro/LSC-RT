import 'dart:async';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';

abstract class VisionDataSource {
  Stream<List<HandPose>> get handStream;
  Stream<List<FaceBounds>> get faceStream;
  bool get isInitialized;

  Future<void> initialize();
  void processFrame(dynamic image, int sensorOrientation);
  void setRotation(int degrees);
  Future<void> dispose();
}
