import '../entities/hand_pose.dart';
import '../repositories/i_sign_repository.dart';
import 'predict_sign_usecase.dart';

/// Caso de uso para acumular y guardar calibraciones de señas LSC.
class CalibrateSignUseCase {
  final ISignRepository _signRepository;
  final PredictSignUseCase _predictUseCase;

  CalibrateSignUseCase(this._signRepository, this._predictUseCase);

  List<double> extractNormalizedFeatures(HandPose handPose) {
    return _predictUseCase.preProcessLandmarks(handPose.landmarks);
  }

  Future<void> saveCalibration(String letter, List<List<double>> samples) async {
    await _signRepository.saveSign(letter, samples);
  }

  Future<void> clearAllCalibrations() async {
    await _signRepository.clearCustomSigns();
  }
}
