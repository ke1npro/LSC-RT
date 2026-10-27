import 'dart:math' as math;
import '../entities/landmark_point.dart';

/// Estado actual del detector de actividad cinemática.
enum GestureTrackingState {
  resting,     // Manos en reposo (bajo la línea del pecho)
  approaching, // Manos ascendiendo hacia la zona de ejecución
  active,      // Gesto en ejecución activa (por encima de la línea del pecho)
  completing,  // Manos descendiendo al reposo (ventana de histéresis)
}

/// Detector de actividad por línea de pecho calibrada (alfa = 0.60).
/// Gestiona la máquina de estados temporal para segmentar automáticamente el gesto.
class ChestActivityDetector {
  final double chestLineAlpha;
  final int minActiveFrames;
  final int maxActiveFrames;
  final int restingHysteresisFrames;

  GestureTrackingState _state = GestureTrackingState.resting;
  final List<List<double>> _currentBuffer = [];
  int _consecutiveRestingFrames = 0;
  int _consecutiveActiveFrames = 0;

  ChestActivityDetector({
    this.chestLineAlpha = 0.60,
    this.minActiveFrames = 8,
    this.maxActiveFrames = 120,
    this.restingHysteresisFrames = 6,
  });

  GestureTrackingState get state => _state;
  bool get isRecording => _state == GestureTrackingState.active || _state == GestureTrackingState.completing;
  int get currentBufferLength => _currentBuffer.length;

  /// Reinicia el detector a su estado base de reposo.
  void reset() {
    _state = GestureTrackingState.resting;
    _currentBuffer.clear();
    _consecutiveRestingFrames = 0;
    _consecutiveActiveFrames = 0;
  }

  /// Procesa un fotograma con las posiciones de hombros, codos y muñecas.
  /// Si se completa un gesto válido, devuelve la secuencia de 8 coordenadas normalizadas por hombros.
  List<List<double>>? processFrame({
    required LandmarkPoint shoulderLeft,
    required LandmarkPoint shoulderRight,
    required LandmarkPoint elbowLeft,
    required LandmarkPoint elbowRight,
    required LandmarkPoint wristLeft,
    required LandmarkPoint wristRight,
  }) {
    // 1. Calcular centro y ancho de hombros
    final double shCenterX = (shoulderLeft.x + shoulderRight.x) / 2.0;
    final double shCenterY = (shoulderLeft.y + shoulderRight.y) / 2.0;

    final double dxSh = shoulderLeft.x - shoulderRight.x;
    final double dySh = shoulderLeft.y - shoulderRight.y;
    double shWidth = math.sqrt(dxSh * dxSh + dySh * dySh);
    if (shWidth < 0.02) shWidth = 0.15; // Cota de seguridad mínima

    // 2. Línea de pecho calibrada: y_pecho = y_hombros + 0.60 * ancho_hombros
    // (En coordenadas de pantalla, Y crece hacia abajo: menor Y significa mayor elevación)
    final double chestLineY = shCenterY + (chestLineAlpha * shWidth);

    // Al menos una muñeca por encima de la línea de pecho indica actividad gestual
    final bool isWristLeftActive = wristLeft.y < chestLineY;
    final bool isWristRightActive = wristRight.y < chestLineY;
    final bool isAnyWristActive = isWristLeftActive || isWristRightActive;

    // Normalización de articulaciones respecto al centro y escala de hombros
    final List<double> normalizedJoints = [
      (elbowLeft.x - shCenterX) / shWidth,
      (elbowLeft.y - shCenterY) / shWidth,
      (elbowRight.x - shCenterX) / shWidth,
      (elbowRight.y - shCenterY) / shWidth,
      (wristLeft.x - shCenterX) / shWidth,
      (wristLeft.y - shCenterY) / shWidth,
      (wristRight.x - shCenterX) / shWidth,
      (wristRight.y - shCenterY) / shWidth,
    ];

    // 3. Máquina de estados
    switch (_state) {
      case GestureTrackingState.resting:
        if (isAnyWristActive) {
          _consecutiveActiveFrames++;
          if (_consecutiveActiveFrames >= 2) {
            _state = GestureTrackingState.active;
            _currentBuffer.clear();
            _currentBuffer.add(normalizedJoints);
            _consecutiveRestingFrames = 0;
          }
        } else {
          _consecutiveActiveFrames = 0;
        }
        return null;

      case GestureTrackingState.approaching:
        // No usado directamente, pasa directo a active
        return null;

      case GestureTrackingState.active:
        _currentBuffer.add(normalizedJoints);

        if (!isAnyWristActive) {
          _consecutiveRestingFrames++;
          _state = GestureTrackingState.completing;
        } else {
          _consecutiveRestingFrames = 0;
        }

        // Si excede la longitud máxima, forzar cierre
        if (_currentBuffer.length >= maxActiveFrames) {
          return _finalizeGesture();
        }
        return null;

      case GestureTrackingState.completing:
        _currentBuffer.add(normalizedJoints);

        if (isAnyWristActive) {
          // Volvió a activarse la mano, continúa el gesto
          _state = GestureTrackingState.active;
          _consecutiveRestingFrames = 0;
        } else {
          _consecutiveRestingFrames++;
          if (_consecutiveRestingFrames >= restingHysteresisFrames) {
            return _finalizeGesture();
          }
        }

        if (_currentBuffer.length >= maxActiveFrames) {
          return _finalizeGesture();
        }
        return null;
    }
  }

  /// Finaliza el gesto y emite el segmento si cumple la cota mínima de fotogramas.
  List<List<double>>? _finalizeGesture() {
    final List<List<double>> result = List<List<double>>.from(_currentBuffer);
    reset();

    if (result.length >= minActiveFrames) {
      return result;
    }
    return null; // Demasiado corto, descartado como ruido de transición
  }
}
