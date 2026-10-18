import 'dart:math' as math;
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';
import '../entities/sign_prediction.dart';
import '../repositories/i_sign_repository.dart';

/// Caso de uso que normaliza las 21 articulaciones de la mano respecto a la muñeca
/// y clasifica la seña LSC contra la base de datos de calibraciones.
class PredictSignUseCase {
  final ISignRepository _signRepository;

  PredictSignUseCase(this._signRepository);

  /// Normaliza los 21 puntos respecto a la muñeca (Landmark 0)
  List<double> preProcessLandmarks(List<LandmarkPoint> landmarks) {
    if (landmarks.length < 21) return [];

    final double baseX = landmarks[0].x;
    final double baseY = landmarks[0].y;

    final List<double> relativeList = [];
    double maxAbs = 0.0;

    for (final lm in landmarks) {
      final double rx = lm.x - baseX;
      final double ry = lm.y - baseY;
      relativeList.add(rx);
      relativeList.add(ry);

      if (rx.abs() > maxAbs) maxAbs = rx.abs();
      if (ry.abs() > maxAbs) maxAbs = ry.abs();
    }

    if (maxAbs == 0.0) maxAbs = 1.0;
    return relativeList.map((val) => val / maxAbs).toList();
  }

  SignPrediction? execute(HandPose handPose) {
    if (!handPose.isValid || !_signRepository.isLoaded) {
      return null;
    }

    final normVec = preProcessLandmarks(handPose.landmarks);
    if (normVec.length != 42) return null;

    final db = _signRepository.signDatabase;
    String bestLetter = '-';
    double minDist = double.infinity;

    db.forEach((letter, samples) {
      for (final sample in samples) {
        if (sample.length != normVec.length) continue;
        double distSq = 0.0;
        for (int i = 0; i < normVec.length; i++) {
          final diff = normVec[i] - sample[i];
          distSq += diff * diff;
        }
        final dist = math.sqrt(distSq);
        if (dist < minDist) {
          minDist = dist;
          bestLetter = letter;
        }
      }
    });

    const double sigma = 0.35;
    final double confidence = math.exp(-(minDist * minDist) / (2 * sigma * sigma));

    if (confidence < 0.35) {
      return SignPrediction(label: '?', confidence: confidence);
    }

    return SignPrediction(
      label: bestLetter,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }
}
