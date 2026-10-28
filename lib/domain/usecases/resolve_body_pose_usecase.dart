import 'dart:math' as math;
import '../entities/arm_skeleton.dart';
import '../entities/body_pose.dart';
import '../entities/face_bounds.dart';
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';

/// Caso de uso que resuelve la cadena cinemática completa (Two-Bone IK),
/// la histéresis de lateralidad y el suavizado temporal (Lerp) para entregar
/// un [BodyPose] listo para consumo o dibujo declarativo. Soporta simultáneamente
/// uno o ambos brazos con estados de suavizado independientes.
class ResolveBodyPoseUseCase {
  LandmarkPoint? _prevRightShoulder;
  LandmarkPoint? _prevRightElbow;
  LandmarkPoint? _prevRightSternum;

  LandmarkPoint? _prevLeftShoulder;
  LandmarkPoint? _prevLeftElbow;
  LandmarkPoint? _prevLeftSternum;

  FaceBounds? _lastKnownFace;
  DateTime? _lastFaceTime;
  bool _singleHandIsRight = true;

  void reset() {
    _prevRightShoulder = null;
    _prevRightElbow = null;
    _prevRightSternum = null;
    _prevLeftShoulder = null;
    _prevLeftElbow = null;
    _prevLeftSternum = null;
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

    // 2. Anclaje de Torso, Esternón y Hombro Base
    final double baseSternumDx;
    final double baseSternumDy;
    final double shoulderSpan;
    final double baseShoulderLevelY;

    if (effectiveFace != null) {
      final fcX = (effectiveFace.centerX - 0.5) * logicalWidth;
      final fcY = (effectiveFace.centerY - 0.5) * logicalHeight;
      final fw = effectiveFace.width * logicalWidth;
      final fh = effectiveFace.height * logicalHeight;

      baseSternumDx = fcX;
      baseSternumDy = fcY + (fh * 0.82);
      shoulderSpan = fw * 1.30;
      baseShoulderLevelY = fcY + (fh * 0.72);
    } else {
      baseSternumDx = 0.0;
      baseSternumDy = logicalHeight * 0.06;
      shoulderSpan = logicalWidth * 0.22;
      baseShoulderLevelY = logicalHeight * 0.02;
    }

    final validHands = hands.where((h) => h.isValid).toList();
    if (validHands.isEmpty) {
      return BodyPose(
        hands: const [],
        arms: const [],
        primaryFace: effectiveFace,
      );
    }

    final List<ArmSkeleton> resolvedArms = [];

    if (validHands.length == 1) {
      // Un solo brazo detectado: usar histéresis de lateralidad
      final hand = validHands.first;
      final wristDx = (hand.wrist.x - 0.5) * logicalWidth;
      final midDx = (hand.middleBase.x - 0.5) * logicalWidth;
      final handMidX = (wristDx + midDx) / 2;
      final distFromMidline = handMidX - baseSternumDx;

      if (distFromMidline > 35) {
        _singleHandIsRight = true;
      } else if (distFromMidline < -35) {
        _singleHandIsRight = false;
      }

      resolvedArms.add(
        _resolveArm(
          hand: hand,
          isRightArm: _singleHandIsRight,
          effectiveFace: effectiveFace,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          baseSternumDx: baseSternumDx,
          baseSternumDy: baseSternumDy,
          shoulderSpan: shoulderSpan,
          baseShoulderLevelY: baseShoulderLevelY,
        ),
      );
    } else {
      // Dos manos detectadas: ordenar por eje X (izquierda y derecha simultáneas)
      final sortedHands = [...validHands.take(2)]
        ..sort((a, b) => a.wrist.x.compareTo(b.wrist.x));

      final leftHand = sortedHands[0];
      final rightHand = sortedHands[1];

      resolvedArms.add(
        _resolveArm(
          hand: leftHand,
          isRightArm: false,
          effectiveFace: effectiveFace,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          baseSternumDx: baseSternumDx,
          baseSternumDy: baseSternumDy,
          shoulderSpan: shoulderSpan,
          baseShoulderLevelY: baseShoulderLevelY,
        ),
      );

      resolvedArms.add(
        _resolveArm(
          hand: rightHand,
          isRightArm: true,
          effectiveFace: effectiveFace,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          baseSternumDx: baseSternumDx,
          baseSternumDy: baseSternumDy,
          shoulderSpan: shoulderSpan,
          baseShoulderLevelY: baseShoulderLevelY,
        ),
      );
    }

    return BodyPose(
      hands: validHands,
      arms: resolvedArms,
      primaryFace: effectiveFace,
    );
  }

  ArmSkeleton _resolveArm({
    required HandPose hand,
    required bool isRightArm,
    required FaceBounds? effectiveFace,
    required double logicalWidth,
    required double logicalHeight,
    required double baseSternumDx,
    required double baseSternumDy,
    required double shoulderSpan,
    required double baseShoulderLevelY,
  }) {
    final wrist = hand.wrist;
    final middleBase = hand.middleBase;

    final wristDx = (wrist.x - 0.5) * logicalWidth;
    final wristDy = (wrist.y - 0.5) * logicalHeight;
    final midDx = (middleBase.x - 0.5) * logicalWidth;
    final midDy = (middleBase.y - 0.5) * logicalHeight;

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

    final double baseShoulderX =
        baseSternumDx + (isRightArm ? shoulderSpan : -shoulderSpan);
    final double baseShoulderY = baseShoulderLevelY;

    final double reachX = wristDx - baseShoulderX;
    final double reachY = wristDy - baseShoulderY;
    final double reachDist = math.sqrt(reachX * reachX + reachY * reachY);

    final double clavicleElevation = (reachY < 0)
        ? (reachY * 0.22).clamp(-shoulderSpan * 0.45, 0.0)
        : (reachY * 0.08).clamp(0.0, shoulderSpan * 0.20);

    final double clavicleProtraction =
        (reachX * 0.15).clamp(-shoulderSpan * 0.35, shoulderSpan * 0.35);

    final double maxReachThreshold = (lUpper + lForearm) * 0.75;
    double stretchX = 0.0;
    double stretchY = 0.0;
    if (reachDist > maxReachThreshold && reachDist > 0.001) {
      final double stretchMag = (reachDist - maxReachThreshold) * 0.25;
      stretchX = (reachX / reachDist) * stretchMag;
      stretchY = (reachY / reachDist) * stretchMag;
    }

    final double targetShoulderX =
        baseShoulderX + clavicleProtraction + stretchX;
    final double targetShoulderY = baseShoulderY + clavicleElevation + stretchY;

    final double targetSternumX =
        baseSternumDx + (clavicleProtraction * 0.35) + (stretchX * 0.2);
    final double targetSternumY =
        baseSternumDy + (clavicleElevation * 0.3) + (stretchY * 0.2);

    LandmarkPoint? prevShoulder =
        isRightArm ? _prevRightShoulder : _prevLeftShoulder;
    LandmarkPoint? prevSternum =
        isRightArm ? _prevRightSternum : _prevLeftSternum;
    LandmarkPoint? prevElbow =
        isRightArm ? _prevRightElbow : _prevLeftElbow;

    final LandmarkPoint shoulder;
    if (prevShoulder == null) {
      shoulder = LandmarkPoint(x: targetShoulderX, y: targetShoulderY);
    } else {
      shoulder = LandmarkPoint(
        x: _lerp(prevShoulder.x, targetShoulderX, 0.45),
        y: _lerp(prevShoulder.y, targetShoulderY, 0.45),
      );
    }

    final LandmarkPoint sternum;
    if (prevSternum == null) {
      sternum = LandmarkPoint(x: targetSternumX, y: targetSternumY);
    } else {
      sternum = LandmarkPoint(
        x: _lerp(prevSternum.x, targetSternumX, 0.45),
        y: _lerp(prevSternum.y, targetSternumY, 0.45),
      );
    }

    if (isRightArm) {
      _prevRightShoulder = shoulder;
      _prevRightSternum = sternum;
    } else {
      _prevLeftShoulder = shoulder;
      _prevLeftSternum = sternum;
    }

    // Cinemática Inversa de 2 Huesos (Two-Bone IK)
    final toWristX = wristDx - shoulder.x;
    final toWristY = wristDy - shoulder.y;
    final rawDist = math.sqrt(toWristX * toWristX + toWristY * toWristY);
    final maxReach = (lUpper + lForearm) * 0.98;
    final minReach = math.max(25.0, (lUpper - lForearm).abs() + 15.0);
    final d = rawDist.clamp(minReach, maxReach);

    final uParX = (rawDist > 0.001) ? (toWristX / rawDist) : 0.0;
    final uParY = (rawDist > 0.001) ? (toWristY / rawDist) : 1.0;

    final cosAlpha =
        ((lUpper * lUpper + d * d - lForearm * lForearm) / (2 * lUpper * d))
            .clamp(-1.0, 1.0);
    final sinAlpha = math.sqrt(math.max(0.0, 1.0 - cosAlpha * cosAlpha));

    double uPerpX = uParY;
    double uPerpY = -uParX;

    final outwardBias = isRightArm ? 1.0 : -1.0;
    if (uPerpX * outwardBias < -0.05) {
      uPerpX = -uPerpX;
      uPerpY = -uPerpY;
    } else if (uPerpX.abs() < 0.25 && uPerpY < 0) {
      uPerpX = -uPerpX;
      uPerpY = -uPerpY;
    }

    final ikElbowX =
        shoulder.x + (uParX * (lUpper * cosAlpha)) + (uPerpX * (lUpper * sinAlpha));
    final ikElbowY =
        shoulder.y + (uParY * (lUpper * cosAlpha)) + (uPerpY * (lUpper * sinAlpha));

    final handDirNormX = (rawHandLen > 0.001) ? (handVecX / rawHandLen) : 0.0;
    final handDirNormY = (rawHandLen > 0.001) ? (handVecY / rawHandLen) : -1.0;
    final handElbowX = wristDx - (handDirNormX * lForearm);
    final handElbowY = wristDy - (handDirNormY * lForearm);

    final blendedElbowX = ikElbowX * 0.75 + handElbowX * 0.25;
    final blendedElbowY = ikElbowY * 0.75 + handElbowY * 0.25;

    final toBlendedX = blendedElbowX - shoulder.x;
    final toBlendedY = blendedElbowY - shoulder.y;
    final blendedDist =
        math.sqrt(toBlendedX * toBlendedX + toBlendedY * toBlendedY);

    final targetElbowX = (blendedDist > 0.001)
        ? (shoulder.x + (toBlendedX / blendedDist) * lUpper)
        : ikElbowX;
    final targetElbowY = (blendedDist > 0.001)
        ? (shoulder.y + (toBlendedY / blendedDist) * lUpper)
        : ikElbowY;

    final LandmarkPoint elbow;
    if (prevElbow == null) {
      elbow = LandmarkPoint(x: targetElbowX, y: targetElbowY);
    } else {
      elbow = LandmarkPoint(
        x: _lerp(prevElbow.x, targetElbowX, 0.40),
        y: _lerp(prevElbow.y, targetElbowY, 0.40),
      );
    }

    if (isRightArm) {
      _prevRightElbow = elbow;
    } else {
      _prevLeftElbow = elbow;
    }

    return ArmSkeleton(
      wrist: LandmarkPoint(x: wristDx, y: wristDy),
      elbow: elbow,
      shoulder: shoulder,
      sternum: sternum,
      isRightArm: isRightArm,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
