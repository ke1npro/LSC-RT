import 'dart:math' as math;
import '../entities/arm_skeleton.dart';
import '../entities/body_pose.dart';
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';

/// Caso de uso que genera la postura sintética [BodyPose] de referencia
/// para el gesto "Wave" (Saludo) según el progreso de animación [0.0 .. 1.0].
class GenerateWaveGuideUseCase {
  BodyPose execute({
    required double animationProgress,
    required double viewportWidth,
  }) {
    final scale = viewportWidth / 400.0;

    final waveAngle = math.sin(animationProgress * 2 * math.pi) * 0.30;
    final fingerWave = math.sin((animationProgress * 2 * math.pi) - 0.5) * 0.12;

    // 1. Cadena cinemática del brazo de referencia
    final sternum = LandmarkPoint(x: 0, y: 230 * scale);
    final shoulder = LandmarkPoint(x: 85 * scale, y: 210 * scale);
    final elbowOscillation = math.sin(animationProgress * 2 * math.pi) * 6 * scale;
    final elbow = LandmarkPoint(x: 45 * scale + elbowOscillation, y: 140 * scale);
    final wrist = LandmarkPoint(x: 15 * scale, y: 40 * scale);

    final arm = ArmSkeleton(
      wrist: wrist,
      elbow: elbow,
      shoulder: shoulder,
      sternum: sternum,
      isRightArm: true,
    );

    // 2. Generación de los 21 puntos articulados de la mano
    final cosW = math.cos(waveAngle);
    final sinW = math.sin(waveAngle);

    LandmarkPoint rotateAndTranslate(double relX, double relY) {
      final rotX = relX * cosW - relY * sinW;
      final rotY = relX * sinW + relY * cosW;
      return LandmarkPoint(x: wrist.x + rotX, y: wrist.y + rotY);
    }

    final points = <LandmarkPoint>[];
    // 0: Muñeca
    points.add(wrist);

    // Bases de los dedos (MCP)
    final fingerBases = [
      [-35.0 * scale, 15.0 * scale],  // 1: Pulgar CMC
      [-24.0 * scale, -25.0 * scale], // 5: Índice MCP
      [-8.0 * scale, -32.0 * scale],  // 9: Medio MCP
      [10.0 * scale, -28.0 * scale],  // 13: Anular MCP
      [26.0 * scale, -20.0 * scale],  // 17: Meñique MCP
    ];

    final p1 = rotateAndTranslate(fingerBases[0][0], fingerBases[0][1]);
    final p5 = rotateAndTranslate(fingerBases[1][0], fingerBases[1][1]);
    final p9 = rotateAndTranslate(fingerBases[2][0], fingerBases[2][1]);
    final p13 = rotateAndTranslate(fingerBases[3][0], fingerBases[3][1]);
    final p17 = rotateAndTranslate(fingerBases[4][0], fingerBases[4][1]);

    // Pulgar (1 -> 2 -> 3 -> 4)
    final p2 = rotateAndTranslate(fingerBases[0][0] - 12.5 * scale, fingerBases[0][1] - 10 * scale);
    final p3 = rotateAndTranslate(fingerBases[0][0] - 22.5 * scale, fingerBases[0][1] - 18 * scale);
    final p4 = rotateAndTranslate(
      fingerBases[0][0] - 31.0 * scale + (fingerWave * 15),
      fingerBases[0][1] - 25 * scale,
    );

    // Índice (5 -> 6 -> 7 -> 8)
    final indexLen = 22.0 * scale;
    final p6 = rotateAndTranslate(fingerBases[1][0] - 4 * scale, fingerBases[1][1] - indexLen);
    final p7 = rotateAndTranslate(fingerBases[1][0] - 6 * scale, fingerBases[1][1] - indexLen * 1.85);
    final p8 = rotateAndTranslate(
      fingerBases[1][0] - 6 * scale + (fingerWave * 18),
      fingerBases[1][1] - indexLen * 2.6,
    );

    // Medio (9 -> 10 -> 11 -> 12)
    final midLen = 25.0 * scale;
    final p10 = rotateAndTranslate(fingerBases[2][0], fingerBases[2][1] - midLen);
    final p11 = rotateAndTranslate(fingerBases[2][0], fingerBases[2][1] - midLen * 1.85);
    final p12 = rotateAndTranslate(
      fingerBases[2][0] + (fingerWave * 20),
      fingerBases[2][1] - midLen * 2.6,
    );

    // Anular (13 -> 14 -> 15 -> 16)
    final ringLen = 23.0 * scale;
    final p14 = rotateAndTranslate(fingerBases[3][0] + 3 * scale, fingerBases[3][1] - ringLen);
    final p15 = rotateAndTranslate(fingerBases[3][0] + 5 * scale, fingerBases[3][1] - ringLen * 1.85);
    final p16 = rotateAndTranslate(
      fingerBases[3][0] + 5 * scale + (fingerWave * 18),
      fingerBases[3][1] - ringLen * 2.6,
    );

    // Meñique (17 -> 18 -> 19 -> 20)
    final pinkyLen = 19.0 * scale;
    final p18 = rotateAndTranslate(fingerBases[4][0] + 5 * scale, fingerBases[4][1] - pinkyLen);
    final p19 = rotateAndTranslate(fingerBases[4][0] + 8 * scale, fingerBases[4][1] - pinkyLen * 1.8);
    final p20 = rotateAndTranslate(
      fingerBases[4][0] + 8 * scale + (fingerWave * 15),
      fingerBases[4][1] - pinkyLen * 2.5,
    );

    final handLandmarks = [
      points[0], // 0
      p1, p2, p3, p4, // 1-4
      p5, p6, p7, p8, // 5-8
      p9, p10, p11, p12, // 9-12
      p13, p14, p15, p16, // 13-16
      p17, p18, p19, p20, // 17-20
    ];

    return BodyPose(
      hands: [HandPose(landmarks: handLandmarks, confidence: 1.0)],
      arms: [arm],
    );
  }
}
