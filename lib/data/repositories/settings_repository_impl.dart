import '../../domain/repositories/i_settings_repository.dart';
import '../datasources/local_storage_datasource.dart';

class SettingsRepositoryImpl implements ISettingsRepository {
  final LocalStorageDataSource _localStorage;

  static const String _keyShowOverlay = 'show_mediapipe_overlay';
  static const String _keyShowFace = 'show_face_detection';
  static const String _keyShowTeachingOverlay = 'show_teaching_mediapipe_overlay';
  static const String _keyModelRotation = 'model_rotation_degrees';

  bool _showMediaPipeOverlay = true;
  bool _showFaceDetection = true;
  bool _showTeachingMediaPipeOverlay = true;
  int _modelRotationDegrees = 90; // Por defecto 90° horario para corregir el desvío de 90° antihorario (CCW)

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
  Future<void> initialize() async {
    _showMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowOverlay)) ?? true;
    _showFaceDetection =
        (await _localStorage.getBool(_keyShowFace)) ?? true;
    _showTeachingMediaPipeOverlay =
        (await _localStorage.getBool(_keyShowTeachingOverlay)) ?? true;
    _modelRotationDegrees =
        (await _localStorage.getInt(_keyModelRotation)) ?? 90;
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
}
