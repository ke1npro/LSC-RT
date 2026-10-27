import 'package:flutter/foundation.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_sign_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  final ISettingsRepository _settingsRepository;
  final ISignRepository _signRepository;

  SettingsViewModel(this._settingsRepository, this._signRepository);

  bool get showMediaPipeOverlay => _settingsRepository.showMediaPipeOverlay;
  bool get showFaceDetection => _settingsRepository.showFaceDetection;
  bool get showTeachingMediaPipeOverlay =>
      _settingsRepository.showTeachingMediaPipeOverlay;
  int get modelRotationDegrees => _settingsRepository.modelRotationDegrees;

  // Estado del Dataset y Overrides
  int get factorySignsCount => _signRepository.factorySignsCount;
  int get customOverridesCount => _signRepository.customOverridesCount;
  bool get hasCustomOverrides => _signRepository.hasCustomOverrides;

  Future<void> initialize() async {
    await _settingsRepository.initialize();
    await _signRepository.initialize();
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

  Future<void> setModelRotationDegrees(int value) async {
    await _settingsRepository.setModelRotationDegrees(value);
    notifyListeners();
  }

  Future<void> restoreFactoryDataset() async {
    await _signRepository.clearCustomSigns();
    notifyListeners();
  }
}
