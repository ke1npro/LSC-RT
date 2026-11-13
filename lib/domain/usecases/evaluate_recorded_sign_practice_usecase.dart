import 'dart:math' as math;
import '../entities/hand_pose.dart';
import '../entities/recorded_sign.dart';

enum PracticeVerdict {
  mastered,
  almostThere,
  needsPractice,
  insufficientHands,
}

class PracticeEvaluationResult {
  final double overallConfidence;
  final double shapeAndMotionScore;
  final double handDetectionRate;
  final int validFrames;
  final int totalEvaluatedFrames;
  final PracticeVerdict verdict;
  final String feedbackMessage;

  const PracticeEvaluationResult({
    required this.overallConfidence,
    required this.shapeAndMotionScore,
    required this.handDetectionRate,
    required this.validFrames,
    required this.totalEvaluatedFrames,
    required this.verdict,
    required this.feedbackMessage,
  });

  int get confidencePercent => (overallConfidence * 100).round().clamp(0, 100);
}

/// Evalúa offline una práctica grabada comparando la secuencia completa de landmarks
/// del intento del usuario contra una seña de referencia [RecordedSign] del diccionario.
///
/// Combina recorte automático del segmento activo, normalización espacial invariante
/// a traslación/escala y alineamiento temporal DTW (Dynamic Time Warping).
class EvaluateRecordedSignPracticeUseCase {
  static const int _resampleSteps = 20;

  PracticeEvaluationResult execute({
    required RecordedSign referenceSign,
    required List<SignFrameLandmarks> attemptFrames,
  }) {
    final reqHands = referenceSign.requiredHands;
    final refValidFrames = referenceSign.frames.where((f) => f.isValidFor(reqHands)).toList();

    if (refValidFrames.isEmpty) {
      return const PracticeEvaluationResult(
        overallConfidence: 0.0,
        shapeAndMotionScore: 0.0,
        handDetectionRate: 0.0,
        validFrames: 0,
        totalEvaluatedFrames: 0,
        verdict: PracticeVerdict.insufficientHands,
        feedbackMessage: 'La seña de referencia no contiene suficientes fotogramas válidos.',
      );
    }

    if (attemptFrames.isEmpty) {
      return const PracticeEvaluationResult(
        overallConfidence: 0.0,
        shapeAndMotionScore: 0.0,
        handDetectionRate: 0.0,
        validFrames: 0,
        totalEvaluatedFrames: 0,
        verdict: PracticeVerdict.insufficientHands,
        feedbackMessage: 'No se capturaron fotogramas en la grabación. Intenta de nuevo.',
      );
    }

    // 1. Recorte automático al segmento activo donde aparecen las manos requeridas
    final firstValidIdx = attemptFrames.indexWhere((f) => f.isValidFor(reqHands));
    final lastValidIdx = attemptFrames.lastIndexWhere((f) => f.isValidFor(reqHands));

    if (firstValidIdx == -1 || lastValidIdx == -1) {
      return PracticeEvaluationResult(
        overallConfidence: 0.0,
        shapeAndMotionScore: 0.0,
        handDetectionRate: 0.0,
        validFrames: 0,
        totalEvaluatedFrames: attemptFrames.length,
        verdict: PracticeVerdict.insufficientHands,
        feedbackMessage: reqHands >= 2
            ? 'No se detectaron ambas manos claramente. Asegúrate de mantener las 2 manos visibles.'
            : 'No se detectó tu mano en la grabación. Mejora la iluminación y encuadre.',
      );
    }

    final activeSegment = attemptFrames.sublist(firstValidIdx, lastValidIdx + 1);
    final activeValidFrames = activeSegment.where((f) => f.isValidFor(reqHands)).toList();
    final detectionRate = activeSegment.isNotEmpty
        ? (activeValidFrames.length / activeSegment.length).clamp(0.0, 1.0)
        : 0.0;

    if (activeValidFrames.length < 4) {
      return PracticeEvaluationResult(
        overallConfidence: 0.0,
        shapeAndMotionScore: 0.0,
        handDetectionRate: detectionRate,
        validFrames: activeValidFrames.length,
        totalEvaluatedFrames: activeSegment.length,
        verdict: PracticeVerdict.insufficientHands,
        feedbackMessage: 'Se detectaron muy pocos fotogramas válidos (${activeValidFrames.length}). Mantén tus manos en cuadro durante toda la seña.',
      );
    }

    // 2. Extraer secuencias de características normalizadas (forma de mano + trayectoria relativa)
    final refSeq = _extractSequenceFeatures(refValidFrames, reqHands);
    final attemptSeq = _extractSequenceFeatures(activeValidFrames, reqHands);

    // 3. Remuestreo temporal uniforme para alinear duraciones distintas
    final refResampled = _resampleSequence(refSeq, _resampleSteps);
    final attemptResampled = _resampleSequence(attemptSeq, _resampleSteps);

    // 4. Distancia DTW normalizada
    final dtwDist = _computeDtwMeanDistance(refResampled, attemptResampled);
    final shapeAndMotionScore = math.exp(-1.35 * dtwDist).clamp(0.0, 1.0);

    // 5. Confianza global ponderada: 80% similitud morfológica/movimiento + 20% estabilidad de detección
    final overallConfidence = ((shapeAndMotionScore * 0.80) + (detectionRate * 0.20))
        .clamp(0.0, 1.0);

    final PracticeVerdict verdict;
    final String feedback;
    if (overallConfidence >= 0.75) {
      verdict = PracticeVerdict.mastered;
      feedback = 'Excelente ejecución. La forma de la mano y el movimiento coinciden con la seña de referencia.';
    } else if (overallConfidence >= 0.50) {
      verdict = PracticeVerdict.almostThere;
      feedback = 'Buen intento. Ajusta ligeramente la postura de los dedos o el ritmo del movimiento para mayor precisión.';
    } else {
      verdict = PracticeVerdict.needsPractice;
      feedback = 'Sigue practicando. Revisa el video de demostración y compara la trayectoria y posición de tu mano.';
    }

    return PracticeEvaluationResult(
      overallConfidence: overallConfidence,
      shapeAndMotionScore: shapeAndMotionScore,
      handDetectionRate: detectionRate,
      validFrames: activeValidFrames.length,
      totalEvaluatedFrames: activeSegment.length,
      verdict: verdict,
      feedbackMessage: feedback,
    );
  }

  List<List<double>> _extractSequenceFeatures(
    List<SignFrameLandmarks> frames,
    int requiredHands,
  ) {
    if (frames.isEmpty) return const [];

    // Muñeca inicial de la mano primaria para trayectoria relativa
    final firstValidHands = _orderedHands(frames.first.hands, requiredHands);
    final baseWristX = firstValidHands.first.wrist.x;
    final baseWristY = firstValidHands.first.wrist.y;

    return frames.map((frame) {
      final ordered = _orderedHands(frame.hands, requiredHands);
      final features = <double>[];

      for (int h = 0; h < requiredHands; h++) {
        final hand = ordered[h];
        final wrist = hand.wrist;
        final middleBase = hand.middleBase;

        final dxScale = middleBase.x - wrist.x;
        final dyScale = middleBase.y - wrist.y;
        final rawScale = math.sqrt(dxScale * dxScale + dyScale * dyScale);
        final scale = rawScale > 0.005 ? rawScale : 1.0;

        // 21 landmarks normalizados por traslación y escala de palma
        for (int i = 0; i < 21; i++) {
          final pt = hand.landmarks[i];
          features.add((pt.x - wrist.x) / scale);
          features.add((pt.y - wrist.y) / scale);
        }

        // Desplazamiento relativo de muñeca respecto al inicio de la seña (peso moderado)
        features.add((wrist.x - baseWristX) * 1.5);
        features.add((wrist.y - baseWristY) * 1.5);
      }

      return features;
    }).toList();
  }

  List<HandPose> _orderedHands(List<HandPose> hands, int requiredHands) {
    final valid = hands.where((h) => h.isValid).toList();
    if (requiredHands >= 2 && valid.length >= 2) {
      final sorted = List<HandPose>.from(valid)
        ..sort((a, b) => a.wrist.x.compareTo(b.wrist.x));
      return sorted.take(2).toList();
    }
    return [valid.first];
  }

  List<List<double>> _resampleSequence(List<List<double>> seq, int targetLen) {
    if (seq.isEmpty) return const [];
    if (seq.length == 1) {
      return List.generate(targetLen, (_) => List<double>.from(seq.first));
    }

    final featDim = seq.first.length;
    final resampled = <List<double>>[];

    for (int t = 0; t < targetLen; t++) {
      final pos = (t * (seq.length - 1)) / (targetLen - 1);
      final idxLow = pos.floor().clamp(0, seq.length - 1);
      final idxHigh = pos.ceil().clamp(0, seq.length - 1);
      final alpha = pos - idxLow;

      final vec = List<double>.filled(featDim, 0.0);
      for (int d = 0; d < featDim; d++) {
        vec[d] = seq[idxLow][d] * (1.0 - alpha) + seq[idxHigh][d] * alpha;
      }
      resampled.add(vec);
    }

    return resampled;
  }

  double _computeDtwMeanDistance(
    List<List<double>> seqA,
    List<List<double>> seqB,
  ) {
    final n = seqA.length;
    final m = seqB.length;
    if (n == 0 || m == 0) return 10.0;

    final dp = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    dp[0][0] = 0.0;

    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        final cost = _frameDistance(seqA[i - 1], seqB[j - 1]);
        final bestPrev = math.min(
          dp[i - 1][j],
          math.min(dp[i][j - 1], dp[i - 1][j - 1]),
        );
        dp[i][j] = cost + bestPrev;
      }
    }

    final totalCost = dp[n][m];
    // Longitud aproximada del camino de alineación
    return totalCost / ((n + m) / 2.0);
  }

  double _frameDistance(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 10.0;
    double sumSq = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sumSq += diff * diff;
    }
    return math.sqrt(sumSq / a.length);
  }
}
