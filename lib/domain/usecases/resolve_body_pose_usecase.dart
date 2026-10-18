import 'dart:math' as math;
import '../entities/arm_skeleton.dart';
import '../entities/body_pose.dart';
import '../entities/face_bounds.dart';
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';

/// Caso de uso que resuelve la cadena cinemática completa (Two-Bone IK),
/// la histéresis de lateralidad y el suavizado temporal (Lerp) para entregar
/// un [BodyPose] listo para consumo o dibujo declarativo.
class ResolveBodyPoseUseCase {
  LandmarkPoint? _prevShoulder;
  LandmarkPoint? _prevElbow;
  FaceBounds? _lastKnownFace;
  DateTime? _lastFaceTime;
  bool _isRightArm = true;

  void reset() {
    _prevShoulder = null;
    _prevElbow = null;
    _lastKnownFace = null;
    _lastFaceTime = null;
  }

  BodyPose execute({
    required List<HandPose> hands,
    required List<FaceBounds> faces,
    required double logicalWidth,
    required double logicalHeight,
  }) {
    final now = DateTime.now();

    // 1. Seguimiento persistente del rostro (evita saltos si un frame no detecta cara)
    final FaceBounds? currentFace = faces.isNotEmpty ? faces.first : null;
    if (currentFace != null) {
      _lastKnownFace = currentFace;
      _lastFaceTime = now;
    } else if (_lastKnownFace != null && _lastFaceTime != null) {
      if (now.difference(_lastFaceTime!).inMilliseconds > 1200) {
        _lastKnownFace = null;
      }
    }
    final FaceBounds? effectiveFace = _lastKnownFace;

    final List<ArmSkeleton> resolvedArms = [];

    for (final hand in hands) {
      if (!hand.isValid) continue;

      final wrist = hand.wrist;
      final middleBase = hand.middleBase;

      // Coordenadas lógicas centradas (origen 0,0 en el centro del viewport)
      final wristDx = (wrist.x - 0.5) * logicalWidth;
      final wristDy = (wrist.y - 0.5) * logicalHeight;
      final midDx = (middleBase.x - 0.5) * logicalWidth;
      final midDy = (middleBase.y - 0.5) * logicalHeight;

      // 2. Anclaje de Torso, Esternón y Hombro
      final double sternumDx;
      final double sternumDy;
      final double shoulderSpan;
      final double shoulderLevelY;

      if (effectiveFace != null) {
        final fcX = (effectiveFace.centerX - 0.5) * logicalWidth;
        final fcY = (effectiveFace.centerY - 0.5) * logicalHeight;
        final fw = effectiveFace.width * logicalWidth;
        final fh = effectiveFace.height * logicalHeight;

        sternumDx = fcX;
        sternumDy = fcY + (fh * 0.82);
        shoulderSpan = fw * 1.30;
        shoulderLevelY = fcY + (fh * 0.72);
      } else {
        sternumDx = 0.0;
        sternumDy = logicalHeight * 0.06;
        shoulderSpan = logicalWidth * 0.22;
        shoulderLevelY = logicalHeight * 0.02;
      }

      // 3. Lateralidad con Histéresis de 35px
      final handMidX = (wristDx + midDx) / 2;
      final distFromMidline = handMidX - sternumDx;
      if (distFromMidline > 35) {
        _isRightArm = true;
      } else if (distFromMidline < -35) {
        _isRightArm = false;
      }

      final targetShoulderX = sternumDx + (_isRightArm ? shoulderSpan : -shoulderSpan);
      final targetShoulderY = shoulderLevelY;

      final LandmarkPoint shoulder;
      if (_prevShoulder == null) {
        shoulder = LandmarkPoint(x: targetShoulderX, y: targetShoulderY);
      } else {
        shoulder = LandmarkPoint(
          x: _lerp(_prevShoulder!.x, targetShoulderX, 0.35),
          y: _lerp(_prevShoulder!.y, targetShoulderY, 0.35),
        );
      }
      _prevShoulder = shoulder;

      // 4. Longitudes antropométricas fisiológicas
      final handVecX = midDx - wristDx;
      final handVecY = midDy - wristDy;
      final rawHandLen = math.sqrt(handVecX * handVecX + handVecY * handVecY);
      final handLen = (rawHandLen > 15) ? rawHandLen : 45.0;

      final double lUpper;
      final double lForearm;
      if (effectiveFace != null) {
        final fh = effectiveFace.height * logicalHeight;
        lUpper = math.max(fh * 1.25, handLen * 2.3);
        lForearm = math.max(fh * 1.10, handLen * 2.0);
      } else {
        lUpper = handLen * 2.4;
        lForearm = handLen * 2.1;
      }

      // 5. Cinemática Inversa de 2 Huesos (Two-Bone Inverse Kinematics)
      final toWristX = wristDx - shoulder.x;
      final toWristY = wristDy - shoulder.y;
      final rawDist = math.sqrt(toWristX * toWristX + toWristY * toWristY);
      final maxReach = (lUpper + lForearm) * 0.98;
      final minReach = math.max(25.0, (lUpper - lForearm).abs() + 15.0);
      final d = rawDist.clamp(minReach, maxReach);

      final uParX = (rawDist > 0.001) ? (toWristX / rawDist) : 0.0;
      final uParY = (rawDist > 0.001) ? (toWristY / rawDist) : 1.0;

      // Ley del Coseno: cos(alpha) en el hombro
      final cosAlpha = ((lUpper * lUpper + d * d - lForearm * lForearm) / (2 * lUpper * d))
          .clamp(-1.0, 1.0);
      final sinAlpha = math.sqrt(math.max(0.0, 1.0 - cosAlpha * cosAlpha));

      // Vector perpendicular para la flexión del codo
      double uPerpX = uParY;
      double uPerpY = -uParX;

      // El codo humano flexiona siempre hacia el EXTERIOR de la caja torácica
      final outwardBias = _isRightArm ? 1.0 : -1.0;
      if (uPerpX * outwardBias < -0.05) {
        uPerpX = -uPerpX;
        uPerpY = -uPerpY;
      } else if (uPerpX.abs() < 0.25 && uPerpY < 0) {
        uPerpX = -uPerpX;
        uPerpY = -uPerpY;
      }

      final ikElbowX = shoulder.x + (uParX * (lUpper * cosAlpha)) + (uPerpX * (lUpper * sinAlpha));
      final ikElbowY = shoulder.y + (uParY * (lUpper * cosAlpha)) + (uPerpY * (lUpper * sinAlpha));

      // 6. Vector de dirección del antebrazo según la muñeca y la mano (25% influencia)
      final handDirNormX = (rawHandLen > 0.001) ? (handVecX / rawHandLen) : 0.0;
      final handDirNormY = (rawHandLen > 0.001) ? (handVecY / rawHandLen) : -1.0;
      final handElbowX = wristDx - (handDirNormX * lForearm);
      final handElbowY = wristDy - (handDirNormY * lForearm);

      final blendedElbowX = ikElbowX * 0.75 + handElbowX * 0.25;
      final blendedElbowY = ikElbowY * 0.75 + handElbowY * 0.25;

      // Re-proyectar rígidamente a la longitud exacta del húmero
      final toBlendedX = blendedElbowX - shoulder.x;
      final toBlendedY = blendedElbowY - shoulder.y;
      final blendedDist = math.sqrt(toBlendedX * toBlendedX + toBlendedY * toBlendedY);

      final targetElbowX = (blendedDist > 0.001)
          ? (shoulder.x + (toBlendedX / blendedDist) * lUpper)
          : ikElbowX;
      final targetElbowY = (blendedDist > 0.001)
          ? (shoulder.y + (toBlendedY / blendedDist) * lUpper)
          : ikElbowY;

      // 7. Suavizado temporal del codo (Lerp)
      final LandmarkPoint elbow;
      if (_prevElbow == null) {
        elbow = LandmarkPoint(x: targetElbowX, y: targetElbowY);
      } else {
        elbow = LandmarkPoint(
          x: _lerp(_prevElbow!.x, targetElbowX, 0.40),
          y: _lerp(_prevElbow!.y, targetElbowY, 0.40),
        );
      }
      _prevElbow = elbow;

      resolvedArms.add(
        ArmSkeleton(
          wrist: LandmarkPoint(x: wristDx, y: wristDy),
          elbow: elbow,
          shoulder: shoulder,
          sternum: LandmarkPoint(x: sternumDx, y: sternumDy),
          isRightArm: _isRightArm,
        ),
      );
    }

    return BodyPose(
      hands: hands,
      arms: resolvedArms,
      primaryFace: effectiveFace,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
