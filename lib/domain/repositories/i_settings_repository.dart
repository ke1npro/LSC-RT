abstract class ISettingsRepository {
  bool get showMediaPipeOverlay;
  bool get showFaceDetection;
  bool get showTeachingMediaPipeOverlay;
  int get modelRotationDegrees;

  Future<void> initialize();
  Future<void> setShowMediaPipeOverlay(bool value);
  Future<void> setShowFaceDetection(bool value);
  Future<void> setShowTeachingMediaPipeOverlay(bool value);
  Future<void> setModelRotationDegrees(int value);
}
