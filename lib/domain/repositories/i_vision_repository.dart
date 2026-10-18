import '../entities/face_bounds.dart';
import '../entities/hand_pose.dart';

abstract class IVisionRepository {
  Stream<List<HandPose>> get handStream;
  Stream<List<FaceBounds>> get faceStream;
  bool get isInitialized;

  Future<void> initialize();
  void processFrame(dynamic image, int sensorOrientation);
  Future<void> dispose();
}
