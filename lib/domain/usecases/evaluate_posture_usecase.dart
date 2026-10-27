import 'dart:math' as math;
import '../entities/avatar_sign_data.dart';
import '../entities/body_pose.dart';
import '../entities/hand_pose.dart';

/// Caso de uso que evalúa el porcentaje de coincidencia postural [0.0 .. 1.0]
/// entre el [BodyPose] real del usuario y el [AvatarFrame] o [BodyPose] guía del tutor.
class EvaluatePostureUseCase {
  double execute({
    required BodyPose userPose,
    BodyPose? guidePose,
    AvatarFrame? referenceFrame,
    required double animationProgress,
  }) {
    if (!userPose.hasHand) {
      return 0.0;
    }

    final userHand = userPose.primaryHand!;
    if (!userHand.isValid) {
      return 0.0;
    }

    // 1. Si tenemos un AvatarFrame de referencia con mano canónica de 21 puntos
    if (referenceFrame != null) {
      final refHand = referenceFrame.rightHand ?? referenceFrame.leftHand;
      if (refHand != null && refHand.length >= 21) {
        return _evaluateHandMatch(userHand, refHand);
      }
    }

    // 2. Fallback heurístico si no hay frame canónico disponible
    final wrist = userHand.wrist;
    final middleTip = userHand.middleTip;
    final dy = middleTip.y - wrist.y;

    final double orientationScore;
    if (dy < -0.05) {
      orientationScore = 0.85;
    } else if (dy < 0.05) {
      orientationScore = 0.65;
    } else {
      orientationScore = 0.35;
    }

    final double armBonus = (userPose.primaryArm != null) ? 0.05 : 0.0;
    final waveModulation =
        0.05 * math.sin(animationProgress * 2 * math.pi).abs();

    return (orientationScore + armBonus + waveModulation).clamp(0.0, 1.0);
  }

  /// Evalúa la similitud morfológica normalizada entre los 21 puntos de la mano del usuario
  /// y los 21 puntos canónicos de referencia, invariante a traslación (centrado en la muñeca).
  double _evaluateHandMatch(HandPose userHand, List<AvatarPoint> refPoints) {
    // Origen de coordenadas: muñeca (punto 0)
    final userWrist = userHand.landmarks[0];
    final refWrist = refPoints[0];

    // Escala de normalización: distancia muñeca a base del dedo medio (punto 9)
    final userMiddleBase = userHand.landmarks[9];
    final refMiddleBase = refPoints[9];

    final userScale = math.sqrt(
      math.pow(userMiddleBase.x - userWrist.x, 2) +
          math.pow(userMiddleBase.y - userWrist.y, 2),
    );
    final refScale = math.sqrt(
      math.pow(refMiddleBase.x - refWrist.x, 2) +
          math.pow(refMiddleBase.y - refWrist.y, 2),
    );

    final safeUserScale = userScale > 0.001 ? userScale : 1.0;
    final safeRefScale = refScale > 0.001 ? refScale : 1.0;

    double totalError = 0.0;
    for (int i = 0; i < 21; i++) {
      final u = userHand.landmarks[i];
      final r = refPoints[i];

      final uNormX = (u.x - userWrist.x) / safeUserScale;
      final uNormY = (u.y - userWrist.y) / safeUserScale;

      final rNormX = (r.x - refWrist.x) / safeRefScale;
      final rNormY = (r.y - refWrist.y) / safeRefScale;

      final dist = math.sqrt(
        math.pow(uNormX - rNormX, 2) + math.pow(uNormY - rNormY, 2),
      );
      totalError += dist;
    }

    final meanError = totalError / 21.0;
    // Un error de 0 produce 1.0; un error de 0.8 o más produce ~0.2
    final score = math.exp(-1.5 * meanError);
    return score.clamp(0.0, 1.0);
  }
}
