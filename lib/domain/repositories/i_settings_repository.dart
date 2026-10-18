abstract class ISettingsRepository {
  bool get showMediaPipeOverlay;
  bool get showFaceDetection;
  bool get showTeachingMediaPipeOverlay;

  Future<void> initialize();
  Future<void> setShowMediaPipeOverlay(bool value);
  Future<void> setShowFaceDetection(bool value);
  Future<void> setShowTeachingMediaPipeOverlay(bool value);
}
