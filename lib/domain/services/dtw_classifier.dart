import 'dart:math' as math;
import '../entities/dtw_gesture_sample.dart';

/// Motor de clasificación y alineamiento temporal elástico (DTW) en Dart puro.
/// Implementa la ventana de banda Sakoe-Chiba (w = 3) y remuestreo temporal lineal exacto a 16 fotogramas.
class DtwClassifier {
  /// Umbral calibrado de distancia DTW (cobertura 80% en LOSO inter-sujeto = 11.32).
  /// Para bancos intra-firmante personalizados, las distancias promedio suelen ser < 8.0.
  final double defaultRejectionThreshold;

  const DtwClassifier({this.defaultRejectionThreshold = 11.32});

  /// Remuestrea linealmente una secuencia de N fotogramas a una longitud fija de 16 fotogramas.
  /// Mantiene estricta paridad con `numpy.interp` sobre matrices temporales normalizadas.
  static List<List<double>> resampleSequence(
    List<List<double>> rawFrames, {
    int targetLen = 16,
  }) {
    final int n = rawFrames.length;
    if (n == 0) return [];
    final int dims = rawFrames[0].length;
    if (n == targetLen) {
      return rawFrames.map((row) => List<double>.from(row)).toList();
    }

    final List<List<double>> resampled = List.generate(
      targetLen,
      (_) => List<double>.filled(dims, 0.0),
    );

    // Mapeo temporal uniforme [0.0, 1.0]
    for (int t = 0; t < targetLen; t++) {
      final double targetT = targetLen > 1 ? t / (targetLen - 1) : 0.0;
      final double origIndex = targetT * (n - 1);
      final int i0 = origIndex.floor().clamp(0, n - 1);
      final int i1 = origIndex.ceil().clamp(0, n - 1);
      final double alpha = (i0 == i1) ? 0.0 : (origIndex - i0);

      for (int d = 0; d < dims; d++) {
        final double val0 = rawFrames[i0][d];
        final double val1 = rawFrames[i1][d];
        resampled[t][d] = (1.0 - alpha) * val0 + alpha * val1;
      }
    }

    return resampled;
  }

  /// Calcula la distancia DTW entre dos secuencias de 16x8 con ventana Sakoe-Chiba (w = 3).
  /// Complejidad temporal O(16 * (2w + 1)) = ~112 operaciones por par de secuencias.
  static double calculateDistance(
    List<List<double>> seqA,
    List<List<double>> seqB, {
    int w = 3,
  }) {
    const int n = 16;
    const int m = 16;
    const int dims = 8;
    const double infinity = 1e9;

    // Matriz de costo acumulado (17 x 17)
    final List<List<double>> cost = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, infinity),
    );
    cost[0][0] = 0.0;

    for (int i = 1; i <= n; i++) {
      final int jMin = math.max(1, i - w);
      final int jMax = math.min(m + 1, i + w + 1);

      for (int j = jMin; j < jMax; j++) {
        // Distancia euclídea entre las articulaciones normalizadas en el paso (i-1) y (j-1)
        double sumSq = 0.0;
        final List<double> aFrame = seqA[i - 1];
        final List<double> bFrame = seqB[j - 1];

        for (int k = 0; k < dims; k++) {
          final double diff = aFrame[k] - bFrame[k];
          sumSq += diff * diff;
        }
        final double dist = math.sqrt(sumSq);

        final double c0 = cost[i - 1][j];
        final double c1 = cost[i][j - 1];
        final double c2 = cost[i - 1][j - 1];

        double minPrev = c0 < c1 ? c0 : c1;
        if (c2 < minPrev) minPrev = c2;

        cost[i][j] = dist + minPrev;
      }
    }

    return cost[n][m];
  }

  /// Clasifica una secuencia desconocida contra el banco de plantillas de referencia (1-NN).
  DtwRecognitionResult? classify(
    DtwSequence querySequence,
    List<DtwGestureTemplate> templates, {
    double? threshold,
  }) {
    if (templates.isEmpty) return null;

    final double effectiveThreshold = threshold ?? defaultRejectionThreshold;
    final List<List<double>> queryMatrix = querySequence.toMatrix();

    double minDistance = double.infinity;
    DtwGestureTemplate? bestTemplate;

    for (final template in templates) {
      final double d = calculateDistance(queryMatrix, template.sequence.toMatrix());
      if (d < minDistance) {
        minDistance = d;
        bestTemplate = template;
      }
    }

    if (bestTemplate == null) return null;

    final bool isAccepted = minDistance <= effectiveThreshold;
    // Confianza normalizada entre 0.0 y 1.0 mediante decaimiento exponencial
    final double confidence = math.exp(-minDistance / effectiveThreshold).clamp(0.0, 1.0);

    return DtwRecognitionResult(
      classId: bestTemplate.classId,
      name: bestTemplate.name,
      distance: minDistance,
      confidence: confidence,
      isAccepted: isAccepted,
    );
  }
}
