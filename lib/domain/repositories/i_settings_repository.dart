abstract class ISettingsRepository {
  bool get showMediaPipeOverlay;
  bool get showFaceDetection;
  bool get showTeachingMediaPipeOverlay;
  int get modelRotationDegrees;
  bool get useGpuDelegate;
  bool get highPerformanceCamera;

  Future<void> initialize();
  Future<void> setShowMediaPipeOverlay(bool value);
  Future<void> setShowFaceDetection(bool value);
  Future<void> setShowTeachingMediaPipeOverlay(bool value);
  Future<void> setModelRotationDegrees(int value);
  Future<void> setUseGpuDelegate(bool value);
  Future<void> setHighPerformanceCamera(bool value);
}
