import 'package:flutter/foundation.dart';
import '../../domain/repositories/i_settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  final ISettingsRepository _settingsRepository;

  SettingsViewModel(this._settingsRepository);

  bool get showMediaPipeOverlay => _settingsRepository.showMediaPipeOverlay;
  bool get showFaceDetection => _settingsRepository.showFaceDetection;
  bool get showTeachingMediaPipeOverlay =>
      _settingsRepository.showTeachingMediaPipeOverlay;

  Future<void> initialize() async {
    await _settingsRepository.initialize();
    notifyListeners();
  }

  Future<void> setShowMediaPipeOverlay(bool value) async {
    await _settingsRepository.setShowMediaPipeOverlay(value);
    notifyListeners();
  }

  Future<void> setShowFaceDetection(bool value) async {
    await _settingsRepository.setShowFaceDetection(value);
    notifyListeners();
  }

  Future<void> setShowTeachingMediaPipeOverlay(bool value) async {
    await _settingsRepository.setShowTeachingMediaPipeOverlay(value);
    notifyListeners();
  }
}
