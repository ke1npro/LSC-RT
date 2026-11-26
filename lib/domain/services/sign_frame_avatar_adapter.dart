import '../entities/avatar_sign_data.dart';
import '../entities/face_bounds.dart';
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';
import '../entities/recorded_sign.dart';
import '../usecases/resolve_body_pose_usecase.dart';

/// Convierte fotogramas de señas grabadas ([SignFrameLandmarks]) en [AvatarFrame]
/// para renderizarlos con el personaje ilustrado [AvatarPosePainter] sin deformación.
class SignFrameAvatarAdapter {
  static const double canonicalWidth = 360.0;
  static const double canonicalHeight = 640.0;
  static const double portraitSourceAspect = canonicalWidth / canonicalHeight;

  static const FaceBounds _syntheticFace = FaceBounds(
    left: 0.38,
    top: 0.17,
    width: 0.24,
    height: 0.16,
  );

  /// Convierte una seña grabada del diccionario ([RecordedSign]) en [AvatarSignData].
  static AvatarSignData toAvatarSignData(
    RecordedSign sign,
    ResolveBodyPoseUseCase poseUseCase,
  ) {
    poseUseCase.reset();
    final avatarFrames = sign.frames
        .map((frame) => toAvatarFrame(frame, poseUseCase))
        .toList(growable: false);

    return AvatarSignData(
      id: sign.id,
      signId: sign.id,
      displayName: sign.word,
      category: sign.category,
      type: sign.isBimanual ? 'BIMANUAL' : 'UNIMANUAL',
      totalFrames: avatarFrames.length,
      fps: sign.fps > 0 ? sign.fps : 20.0,
      durationSeconds: sign.durationMs / 1000.0,
      apexFrame: avatarFrames.isEmpty ? 0 : avatarFrames.length ~/ 2,
      pedagogicalMetadata: const PedagogicalMetadata(
        description: 'Seña grabada en tu diccionario personal.',
        instructions: 'Reproduce la secuencia capturada en el diccionario.',
        handshapeDescription: 'Configuración capturada.',
        movementDescription: 'Movimiento grabado.',
        locationDescription: 'Espacio frontal.',
      ),
      frames: avatarFrames,
      sourceAspect: portraitSourceAspect,
      isFromDictionary: true,
    );
  }

  /// Construye un [AvatarFrame] a partir de [frame] usando [poseUseCase]
  /// en un lienzo canónico vertical 9:16.
  static AvatarFrame toAvatarFrame(
    SignFrameLandmarks frame,
    ResolveBodyPoseUseCase poseUseCase,
  ) {
    final pose = poseUseCase.execute(
      hands: frame.hands,
      faces: const [_syntheticFace],
      logicalWidth: canonicalWidth,
      logicalHeight: canonicalHeight,
    );

    final Map<String, AvatarPoint> torso = {
      'nose': AvatarPoint(_syntheticFace.centerX, _syntheticFace.centerY),
      'left_shoulder': const AvatarPoint(0.66, 0.365),
      'right_shoulder': const AvatarPoint(0.34, 0.365),
    };

    for (final arm in pose.arms) {
      // En pantalla (espejo frente al usuario), x > 0.5 corresponde al lado
      // izquierdo del personaje (shoulderL) y x < 0.5 al lado derecho (shoulderR).
      final prefix = arm.isRightArm ? 'left' : 'right';
      torso['${prefix}_shoulder'] = _logicalToNormalized(arm.shoulder);
      torso['${prefix}_elbow'] = _logicalToNormalized(arm.elbow);
      torso['${prefix}_wrist'] = _logicalToNormalized(arm.wrist);
    }

    List<AvatarPoint>? leftHandPts;
    List<AvatarPoint>? rightHandPts;

    final validHands = frame.hands.where((h) => h.isValid).toList();
    if (validHands.length == 1) {
      final h = validHands.first;
      final isScreenRight = _isScreenRightHand(h);
      if (isScreenRight) {
        leftHandPts = _convertHand(h);
      } else {
        rightHandPts = _convertHand(h);
      }
    } else if (validHands.length >= 2) {
      final sorted = [...validHands.take(2)]
        ..sort((a, b) => a.wrist.x.compareTo(b.wrist.x));
      rightHandPts = _convertHand(sorted[0]);
      leftHandPts = _convertHand(sorted[1]);
    }

    return AvatarFrame(
      pose: torso,
      leftHand: leftHandPts,
      rightHand: rightHandPts,
      hasLeftHand: leftHandPts != null,
      hasRightHand: rightHandPts != null,
    );
  }

  static bool _isScreenRightHand(HandPose hand) {
    if (hand.wrist.x >= 0.5) return true;
    return false;
  }

  static AvatarPoint _logicalToNormalized(LandmarkPoint p) {
    return AvatarPoint(
      (p.x / canonicalWidth) + 0.5,
      (p.y / canonicalHeight) + 0.5,
      p.z,
    );
  }

  static List<AvatarPoint> _convertHand(HandPose hand) {
    return hand.landmarks
        .take(21)
        .map((pt) => AvatarPoint(pt.x, pt.y, pt.z))
        .toList();
  }
}
