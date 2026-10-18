import 'dart:math' as math;
import '../entities/body_pose.dart';

/// Caso de uso que evalúa el porcentaje de coincidencia postural [0.0 .. 1.0]
/// entre el [BodyPose] real del usuario y el [BodyPose] guía del tutor.
class EvaluatePostureUseCase {
  double execute({
    required BodyPose userPose,
    required BodyPose guidePose,
    required double animationProgress,
  }) {
    if (!userPose.hasHand) {
      return 0.0;
    }

    final userHand = userPose.primaryHand!;
    final userArm = userPose.primaryArm;

    if (!userHand.isValid) {
      return 0.0;
    }

    // Evaluación de orientación de la mano (dedos extendidos hacia arriba)
    final wrist = userHand.wrist;
    final middleTip = userHand.middleTip;
    final dy = middleTip.y - wrist.y;

    // Dedos hacia arriba (dy < 0 en coordenadas estándar)
    final double orientationScore;
    if (dy < -0.05) {
      orientationScore = 0.90;
    } else if (dy < 0.05) {
      orientationScore = 0.70;
    } else {
      orientationScore = 0.40;
    }

    // Estabilidad del brazo si está resuelto
    final double armBonus = (userArm != null) ? 0.05 : 0.0;

    // Modulación rítmica suave con la fase del Wave
    final waveModulation = 0.05 * math.sin(animationProgress * 2 * math.pi).abs();

    final totalScore = (orientationScore + armBonus + waveModulation).clamp(0.0, 1.0);
    return totalScore;
  }
}
