import '../../core/config/offline_video_config.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../datasources/local_storage_datasource.dart';

class SettingsRepositoryImpl implements ISettingsRepository {
  final LocalStorageDataSource _localStorage;

  static const String _keyShowOverlay = 'show_mediapipe_overlay';
  static const String _keyShowFace = 'show_face_detection';
  static const String _keyShowTeachingOverlay = 'show_teaching_mediapipe_overlay';
  static const String _keyModelRotation = 'model_rotation_degrees';
  static const String _keyUseGpu = 'use_gpu_delegate';
  static const String _keyHighPerfCamera = 'high_performance_camera';
  static const String _keyHasSeenOnboarding = 'has_seen_onboarding';
  static const String _keyOfflineVideoFps = 'offline_video_fps';
  static const String _keyOfflineQualityPreset = 'offline_quality_preset';

  bool _showMediaPipeOverlay = true;
  bool _showFaceDetection = false;
  bool _showTeachingMediaPipeOverlay = true;
  int _modelRotationDegrees = 270; // Por defecto 270° para orientación vertical correcta sin inversión
  bool _useGpuDelegate = false;
  bool _highPerformanceCamera = true;
  bool _hasSeenOnboarding = false;
  int _offlineVideoFps = OfflineVideoConfig.defaultFps;
  String _offlineQualityPreset = OfflineVideoConfig.defaultPreset;

  SettingsRepositoryImpl(this._localStorage);

  @override
  bool get showMediaPipeOverlay => _showMediaPipeOverlay;

  @override
  bool get showFaceDetection => _showFaceDetection;

  @override
  bool get showTeachingMediaPipeOverlay => _showTeachingMediaPipeOverlay;

  @override
  int get modelRotationDegrees => _modelRotationDegrees;

  @override
  bool get useGpuDelegate => _useGpuDelegate;

  @override
  bool get highPerformanceCamera => _highPerformanceCamera;

  @override
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  @override
  int get offlineVideoFps => _offlineVideoFps;

  @override
  String get offlineQualityPreset => _offlineQualityPreset;

  @override
  Future<void> initialize() async {
    _showMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowOverlay)) ?? true;
    _showFaceDetection =
        (await _localStorage.getBool(_keyShowFace)) ?? false;
    _showTeachingMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowTeachingOverlay)) ?? true;
    _modelRotationDegrees =
        (await _localStorage.getInt(_keyModelRotation)) ?? 270;
    _useGpuDelegate =
        (await _localStorage.getBool(_keyUseGpu)) ?? false;
    _highPerformanceCamera =
        (await _localStorage.getBool(_keyHighPerfCamera)) ?? true;
    _hasSeenOnboarding =
        (await _localStorage.getBool(_keyHasSeenOnboarding)) ?? false;
    _offlineVideoFps = OfflineVideoConfig.sanitizeFps(
      (await _localStorage.getInt(_keyOfflineVideoFps)) ??
          OfflineVideoConfig.defaultFps,
    );
    _offlineQualityPreset = OfflineVideoConfig.sanitizePreset(
      (await _localStorage.getString(_keyOfflineQualityPreset)) ??
          OfflineVideoConfig.defaultPreset,
    );
  }

  @override
  Future<void> setShowMediaPipeOverlay(bool value) async {
    _showMediaPipeOverlay = value;
    await _localStorage.setBool(_keyShowOverlay, value);
  }

  @override
  Future<void> setShowFaceDetection(bool value) async {
    _showFaceDetection = value;
    await _localStorage.setBool(_keyShowFace, value);
  }

  @override
  Future<void> setShowTeachingMediaPipeOverlay(bool value) async {
    _showTeachingMediaPipeOverlay = value;
    await _localStorage.setBool(_keyShowTeachingOverlay, value);
  }

  @override
  Future<void> setModelRotationDegrees(int value) async {
    _modelRotationDegrees = value;
    await _localStorage.setInt(_keyModelRotation, value);
  }

  @override
  Future<void> setUseGpuDelegate(bool value) async {
    _useGpuDelegate = value;
    await _localStorage.setBool(_keyUseGpu, value);
  }

  @override
  Future<void> setHighPerformanceCamera(bool value) async {
    _highPerformanceCamera = value;
    await _localStorage.setBool(_keyHighPerfCamera, value);
  }

  @override
  Future<void> setHasSeenOnboarding(bool value) async {
    _hasSeenOnboarding = value;
    await _localStorage.setBool(_keyHasSeenOnboarding, value);
  }

  @override
  Future<void> setOfflineVideoFps(int value) async {
    _offlineVideoFps = OfflineVideoConfig.sanitizeFps(value);
    await _localStorage.setInt(_keyOfflineVideoFps, _offlineVideoFps);
  }

  @override
  Future<void> setOfflineQualityPreset(String value) async {
    _offlineQualityPreset = OfflineVideoConfig.sanitizePreset(value);
    await _localStorage.setString(_keyOfflineQualityPreset, _offlineQualityPreset);
  }
}
