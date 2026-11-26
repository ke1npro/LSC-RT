abstract class ISettingsRepository {
  bool get showMediaPipeOverlay;
  bool get showFaceDetection;
  bool get showTeachingMediaPipeOverlay;
  int get modelRotationDegrees;
  bool get useGpuDelegate;
  bool get highPerformanceCamera;
  bool get hasSeenOnboarding;
  int get offlineVideoFps;
  String get offlineQualityPreset;

  Future<void> initialize();
  Future<void> setShowMediaPipeOverlay(bool value);
  Future<void> setShowFaceDetection(bool value);
  Future<void> setShowTeachingMediaPipeOverlay(bool value);
  Future<void> setModelRotationDegrees(int value);
  Future<void> setUseGpuDelegate(bool value);
  Future<void> setHighPerformanceCamera(bool value);
  Future<void> setHasSeenOnboarding(bool value);
  Future<void> setOfflineVideoFps(int value);
  Future<void> setOfflineQualityPreset(String value);
}
