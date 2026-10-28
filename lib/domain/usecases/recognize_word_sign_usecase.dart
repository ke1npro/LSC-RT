import 'dart:math' as math;
import '../entities/body_pose.dart';
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';
import '../entities/sign_prediction.dart';

/// Caso de uso que reconoce señas dinámicas y fonológicas esenciales de LSC
/// (tanto bimanuales como unimanuales de alta frecuencia) complementando
/// la detección estática de letras individuales.
class RecognizeWordSignUseCase {
  final List<List<LandmarkPoint>> _leftWristHistory = [];
  final List<List<LandmarkPoint>> _rightWristHistory = [];
  final List<double> _bimanualDistHistory = [];
  static const int _historyLimit = 24;

  void reset() {
    _leftWristHistory.clear();
    _rightWristHistory.clear();
    _bimanualDistHistory.clear();
  }

  SignPrediction? execute({
    required List<HandPose> hands,
    required BodyPose? pose,
  }) {
    final validHands = hands.where((h) => h.isValid).toList();
    if (validHands.isEmpty) {
      reset();
      return null;
    }

    // 1. Clasificación de lateralidad por coordenadas X
    final HandPose dominantHand;
    final HandPose? secondaryHand;

    if (validHands.length >= 2) {
      final sorted = [...validHands.take(2)]
        ..sort((a, b) => a.wrist.x.compareTo(b.wrist.x));
      // En vista frontal estándar, x menor es izquierda del usuario en pantalla
      final leftH = sorted[0];
      final rightH = sorted[1];
      dominantHand = rightH;
      secondaryHand = leftH;

      _recordFrame(leftH.wrist, rightH.wrist);
    } else {
      dominantHand = validHands.first;
      secondaryHand = null;
      _recordFrame(null, dominantHand.wrist);
    }

    // Altura del esternón y hombros de referencia
    final double shoulderLevelY;
    if (pose != null && pose.arms.isNotEmpty) {
      shoulderLevelY = pose.arms.first.shoulder.y;
    } else if (pose?.primaryFace != null) {
      shoulderLevelY = (pose!.primaryFace!.centerY - 0.5) * 800 + 40;
    } else {
      shoulderLevelY = 0.0;
    }

    // 2. Reconocimiento BIMANUAL (cuando ambas manos están en escena)
    if (secondaryHand != null && validHands.length >= 2) {
      final bimanualResult = _classifyBimanual(
        leftHand: secondaryHand,
        rightHand: dominantHand,
        shoulderY: shoulderLevelY,
      );
      if (bimanualResult != null) return bimanualResult;
    }

    // 3. Reconocimiento UNIMANUAL de palabras core (YO, TÚ, BIEN, MAL, etc.)
    if (validHands.length == 1) {
      final unimanualResult = _classifyUnimanual(
        hand: dominantHand,
        shoulderY: shoulderLevelY,
      );
      if (unimanualResult != null) return unimanualResult;
    }

    return null;
  }

  void _recordFrame(LandmarkPoint? leftW, LandmarkPoint? rightW) {
    if (leftW != null && rightW != null) {
      final dx = rightW.x - leftW.x;
      final dy = rightW.y - leftW.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      _bimanualDistHistory.add(dist);
      if (_bimanualDistHistory.length > _historyLimit) {
        _bimanualDistHistory.removeAt(0);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LÓGICA BIMANUAL
  // ---------------------------------------------------------------------------

  SignPrediction? _classifyBimanual({
    required HandPose leftHand,
    required HandPose rightHand,
    required double shoulderY,
  }) {
    final lw = leftHand.wrist;
    final rw = rightHand.wrist;
    final dx = (rw.x - lw.x).abs();
    final dy = (rw.y - lw.y).abs();
    final dist = math.sqrt(dx * dx + dy * dy);

    final lGeom = _analyzeGeometry(leftHand.landmarks);
    final rGeom = _analyzeGeometry(rightHand.landmarks);

    // A. FAMILIA: Ambas manos uniendo índice y pulgar en círculos ('F') y tocándose en el pecho
    final lPinch = lGeom.isPinching;
    final rPinch = rGeom.isPinching;
    if (lPinch && rPinch && dist < 0.22) {
      return const SignPrediction(label: 'FAMILIA', confidence: 0.95);
    }

    // B. BUENOS DÍAS: Manos partiendo juntas en el centro y abriendo hacia afuera
    if (_bimanualDistHistory.length >= 6) {
      final iniDist = _bimanualDistHistory.take(3).reduce((a, b) => a + b) / 3;
      final endDist = _bimanualDistHistory.reversed.take(3).reduce((a, b) => a + b) / 3;
      if (endDist - iniDist > 0.08 && lGeom.isOpen && rGeom.isOpen) {
        return const SignPrediction(label: 'BUENOS DÍAS', confidence: 0.94);
      }
    }

    // C. TRABAJAR: Ambos puños cerrados con alternancia vertical o contacto
    if (lGeom.isFist && rGeom.isFist && dist < 0.24) {
      return const SignPrediction(label: 'TRABAJAR', confidence: 0.93);
    }

    // D. DIFERENTE: Ambos dedos índices extendidos cruzándose o separándose
    if (lGeom.isPointing && rGeom.isPointing && dist < 0.26) {
      return const SignPrediction(label: 'DIFERENTE', confidence: 0.92);
    }

    // E. ¿QUÉ?: Ambas palmas abiertas con muñecas separadas oscilando horizontalmente
    if (lGeom.isOpen && rGeom.isOpen && dist > 0.20 && dist < 0.55 && dy < 0.12) {
      return const SignPrediction(label: '¿QUÉ?', confidence: 0.88);
    }

    // F. HERMANO: Dedos índices juntos en horizontal o rozándose
    if (lGeom.isPointing && rGeom.isPointing && dist < 0.15) {
      return const SignPrediction(label: 'HERMANO', confidence: 0.91);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // LÓGICA UNIMANUAL (Palabras Core)
  // ---------------------------------------------------------------------------

  SignPrediction? _classifyUnimanual({
    required HandPose hand,
    required double shoulderY,
  }) {
    final geom = _analyzeGeometry(hand.landmarks);
    final wrist = hand.wrist;

    // A. BIEN: Puño cerrado con pulgar estrictamente hacia arriba
    if (geom.isThumbUp) {
      return const SignPrediction(label: 'BIEN', confidence: 0.96);
    }

    // B. MAL: Puño cerrado con pulgar estrictamente hacia abajo
    if (geom.isThumbDown) {
      return const SignPrediction(label: 'MAL', confidence: 0.96);
    }

    // C. YO: Dedo índice extendido apuntando hacia el propio pecho
    // La punta del índice está cerca del eje central y a la altura del torso
    if (geom.isPointing) {
      final indexTip = hand.landmarks[8];
      // Si la punta apunta hacia el cuerpo o la muñeca está a la altura del pecho
      if (indexTip.y > 0.35 && indexTip.y < 0.75 && (indexTip.x - 0.5).abs() < 0.18) {
        return const SignPrediction(label: 'YO', confidence: 0.94);
      }

      // D. TÚ: Dedo índice extendido apuntando hacia adelante/cámara
      if (indexTip.y <= 0.40) {
        return const SignPrediction(label: 'TÚ', confidence: 0.91);
      }
    }

    // E. GRACIAS: Mano abierta partiendo cerca de la boca/barbilla (y < 0.40)
    if (geom.isOpen && wrist.y < 0.42 && (wrist.x - 0.5).abs() < 0.18) {
      return const SignPrediction(label: 'GRACIAS', confidence: 0.92);
    }

    // F. HOLA: Mano abierta junto a la sien/oreja
    if (geom.isOpen && wrist.y < 0.35 && (wrist.x - 0.5).abs() > 0.18) {
      return const SignPrediction(label: 'HOLA', confidence: 0.90);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // ANÁLISIS GEOMÉTRICO DE LANDMARKS
  // ---------------------------------------------------------------------------

  _HandGeometry _analyzeGeometry(List<LandmarkPoint> lm) {
    if (lm.length < 21) {
      return const _HandGeometry(
        isThumbUp: false,
        isThumbDown: false,
        isPointing: false,
        isOpen: false,
        isFist: false,
        isPinching: false,
      );
    }

    final wrist = lm[0];
    final thumbTip = lm[4];
    final thumbMcp = lm[2];
    final indexTip = lm[8];
    final indexPip = lm[6];
    final middleTip = lm[12];
    final middlePip = lm[10];
    final ringTip = lm[16];
    final ringPip = lm[14];
    final pinkyTip = lm[20];
    final pinkyPip = lm[18];

    double dist(LandmarkPoint a, LandmarkPoint b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    // Un dedo está plegado si su punta está más cerca de la muñeca que su PIP
    final idxFolded = dist(indexTip, wrist) <= dist(indexPip, wrist) * 1.08;
    final midFolded = dist(middleTip, wrist) <= dist(middlePip, wrist) * 1.08;
    final rngFolded = dist(ringTip, wrist) <= dist(ringPip, wrist) * 1.08;
    final pnkFolded = dist(pinkyTip, wrist) <= dist(pinkyPip, wrist) * 1.08;

    final isFist = idxFolded && midFolded && rngFolded && pnkFolded;
    final isOpen = !idxFolded && !midFolded && !rngFolded && !pnkFolded;
    final isPointing = !idxFolded && midFolded && rngFolded && pnkFolded;

    // Pulgar arriba / abajo
    final otherMinY = math.min(
      math.min(indexTip.y, middleTip.y),
      math.min(ringTip.y, pinkyTip.y),
    );
    final otherMaxY = math.max(
      math.max(indexTip.y, middleTip.y),
      math.max(ringTip.y, pinkyTip.y),
    );

    final isThumbUp = isFist &&
        (thumbTip.y < thumbMcp.y - 0.03) &&
        (thumbTip.y < otherMinY - 0.02);

    final isThumbDown = isFist &&
        (thumbTip.y > thumbMcp.y + 0.03) &&
        (thumbTip.y > otherMaxY + 0.02);

    // Pellizco / Círculo (Índice y Pulgar juntos)
    final pinchDist = dist(thumbTip, indexTip);
    final isPinching = pinchDist < 0.065;

    return _HandGeometry(
      isThumbUp: isThumbUp,
      isThumbDown: isThumbDown,
      isPointing: isPointing,
      isOpen: isOpen,
      isFist: isFist,
      isPinching: isPinching,
    );
  }
}

class _HandGeometry {
  final bool isThumbUp;
  final bool isThumbDown;
  final bool isPointing;
  final bool isOpen;
  final bool isFist;
  final bool isPinching;

  const _HandGeometry({
    required this.isThumbUp,
    required this.isThumbDown,
    required this.isPointing,
    required this.isOpen,
    required this.isFist,
    required this.isPinching,
  });
}
