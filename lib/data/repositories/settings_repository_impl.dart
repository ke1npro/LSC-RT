import '../../domain/repositories/i_settings_repository.dart';
import '../datasources/local_storage_datasource.dart';

class SettingsRepositoryImpl implements ISettingsRepository {
  final LocalStorageDataSource _localStorage;

  static const String _keyShowOverlay = 'show_mediapipe_overlay';
  static const String _keyShowFace = 'show_face_detection';
  static const String _keyShowTeachingOverlay = 'show_teaching_mediapipe_overlay';

  bool _showMediaPipeOverlay = true;
  bool _showFaceDetection = true;
  bool _showTeachingMediaPipeOverlay = true;

  SettingsRepositoryImpl(this._localStorage);

  @override
  bool get showMediaPipeOverlay => _showMediaPipeOverlay;

  @override
  bool get showFaceDetection => _showFaceDetection;

  @override
  bool get showTeachingMediaPipeOverlay => _showTeachingMediaPipeOverlay;

  @override
  Future<void> initialize() async {
    _showMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowOverlay)) ?? true;
    _showFaceDetection =
        (await _localStorage.getBool(_keyShowFace)) ?? true;
    _showTeachingMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowTeachingOverlay)) ?? true;
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
}
