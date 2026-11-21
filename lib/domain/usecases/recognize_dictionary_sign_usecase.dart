import 'dart:math' as math;
import '../entities/hand_pose.dart';
import '../entities/recorded_sign.dart';
import '../entities/sign_prediction.dart';
import '../repositories/i_dictionary_repository.dart';

/// Reconoce señas en tiempo real comparando una ventana móvil de fotogramas
/// contra las señas grabadas por el usuario en [IDictionaryRepository].
///
/// No contiene reglas ni palabras hardcodeadas: si el diccionario está vacío,
/// retorna `null`. Soporta señas unimanuales (1 mano) y bimanuales (2 manos)
/// mediante normalización espacial invariante a traslación/escala y alineamiento DTW.
class RecognizeDictionarySignUseCase {
  final IDictionaryRepository _dictionaryRepository;

  static const int _resampleSteps = 12;
  static const int _maxBufferLength = 24;
  static const int _minEvalFrames = 4;
  static const double _minCandidateConfidence = 0.45;
  static const double _mirrorPenalty = 1.08;

  final List<List<HandPose>> _liveBuffer = [];
  List<_PreparedSignTemplate> _cachedTemplates = const [];
  String _cachedSignature = '';

  RecognizeDictionarySignUseCase(this._dictionaryRepository);

  void reset() {
    _liveBuffer.clear();
  }

  SignPrediction? execute({
    required List<HandPose> hands,
  }) {
    final validHands = hands.where((h) => h.isValid).toList();
    if (validHands.isEmpty) {
      reset();
      return null;
    }

    final signs = _dictionaryRepository.allSigns;
    if (signs.isEmpty) {
      reset();
      return null;
    }

    _ensureTemplatesSynced(signs);
    if (_cachedTemplates.isEmpty) {
      return null;
    }

    final activeHandCount = validHands.length >= 2 ? 2 : 1;

    // Si cambió la cantidad de manos (1 <-> 2), reiniciar ventana para evitar mezclar dimensiones
    if (_liveBuffer.isNotEmpty) {
      final prevCount = _liveBuffer.last.length >= 2 ? 2 : 1;
      if (prevCount != activeHandCount) {
        _liveBuffer.clear();
      }
    }

    _liveBuffer.add(validHands);
    if (_liveBuffer.length > _maxBufferLength) {
      _liveBuffer.removeAt(0);
    }

    if (_liveBuffer.length < _minEvalFrames) {
      return const SignPrediction(label: '?', confidence: 0.0);
    }

    final candidates = _cachedTemplates
        .where((t) => t.requiredHands == activeHandCount)
        .toList();

    if (candidates.isEmpty) {
      return const SignPrediction(label: '?', confidence: 0.0);
    }

    // Evaluar ventana reciente (hasta los últimos 18 frames)
    final windowStart = math.max(0, _liveBuffer.length - 18);
    final windowFrames = _liveBuffer.sublist(windowStart);
    final queryRaw = _extractSequenceFeatures(windowFrames, activeHandCount, mirrorX: false);
    if (queryRaw.isEmpty) {
      return const SignPrediction(label: '?', confidence: 0.0);
    }
    final querySeq = _resampleSequence(queryRaw, _resampleSteps);

    String? bestWord;
    double bestDistance = double.infinity;

    for (final template in candidates) {
      final directDist = _computeDtwMeanDistance(querySeq, template.directSequence);
      final mirroredDist =
          _computeDtwMeanDistance(querySeq, template.mirroredSequence) * _mirrorPenalty;
      final effectiveDist = math.min(directDist, mirroredDist);

      if (effectiveDist < bestDistance) {
        bestDistance = effectiveDist;
        bestWord = template.word;
      }
    }

    if (bestWord == null || bestDistance.isInfinite) {
      return const SignPrediction(label: '?', confidence: 0.0);
    }

    final confidence = math.exp(-1.25 * bestDistance).clamp(0.0, 1.0);
    if (confidence < _minCandidateConfidence) {
      return SignPrediction(label: '?', confidence: confidence);
    }

    return SignPrediction(
      label: bestWord,
      confidence: confidence,
    );
  }

  void _ensureTemplatesSynced(List<RecordedSign> signs) {
    final signature = signs
        .map((s) => '${s.id}:${s.word}:${s.requiredHands}:${s.frameCount}')
        .join('|');
    if (signature == _cachedSignature) return;

    final prepared = <_PreparedSignTemplate>[];
    for (final sign in signs) {
      final reqHands = sign.requiredHands >= 2 ? 2 : 1;
      final validFrameHands = sign.frames
          .where((f) => f.isValidFor(reqHands))
          .map((f) => f.hands.where((h) => h.isValid).toList())
          .toList();
      if (validFrameHands.isEmpty) continue;

      final directRaw = _extractSequenceFeatures(validFrameHands, reqHands, mirrorX: false);
      final mirroredRaw = _extractSequenceFeatures(validFrameHands, reqHands, mirrorX: true);
      if (directRaw.isEmpty || mirroredRaw.isEmpty) continue;

      prepared.add(
        _PreparedSignTemplate(
          word: sign.word,
          requiredHands: reqHands,
          directSequence: _resampleSequence(directRaw, _resampleSteps),
          mirroredSequence: _resampleSequence(mirroredRaw, _resampleSteps),
        ),
      );
    }

    _cachedTemplates = prepared;
    _cachedSignature = signature;
  }

  List<List<double>> _extractSequenceFeatures(
    List<List<HandPose>> frameHands,
    int requiredHands, {
    required bool mirrorX,
  }) {
    if (frameHands.isEmpty) return const [];

    final double xSign = mirrorX ? -1.0 : 1.0;
    final firstOrdered = _orderedHands(frameHands.first, requiredHands, mirrorX: mirrorX);
    final baseWristX = firstOrdered.first.wrist.x;
    final baseWristY = firstOrdered.first.wrist.y;

    return frameHands.map((handsInFrame) {
      final ordered = _orderedHands(handsInFrame, requiredHands, mirrorX: mirrorX);
      final features = <double>[];

      for (int h = 0; h < requiredHands; h++) {
        final hand = ordered[h];
        final wrist = hand.wrist;
        final middleBase = hand.middleBase;

        final dxScale = middleBase.x - wrist.x;
        final dyScale = middleBase.y - wrist.y;
        final rawScale = math.sqrt(dxScale * dxScale + dyScale * dyScale);
        final scale = rawScale > 0.005 ? rawScale : 1.0;

        // 21 landmarks normalizados (invariante a posición y tamaño de mano)
        for (int i = 0; i < 21; i++) {
          final pt = hand.landmarks[i];
          features.add(((pt.x - wrist.x) / scale) * xSign);
          features.add((pt.y - wrist.y) / scale);
        }

        // Trayectoria relativa de la muñeca dentro de la ventana
        features.add(((wrist.x - baseWristX) * 1.4) * xSign);
        features.add((wrist.y - baseWristY) * 1.4);
      }

      // Para señas bimanuales, añadir vector relativo entre ambas muñecas
      if (requiredHands >= 2 && ordered.length >= 2) {
        final lw = ordered[0].wrist;
        final rw = ordered[1].wrist;
        features.add(((rw.x - lw.x) * 1.4) * xSign);
        features.add((rw.y - lw.y) * 1.4);
      }

      return features;
    }).toList();
  }

  List<HandPose> _orderedHands(
    List<HandPose> hands,
    int requiredHands, {
    required bool mirrorX,
  }) {
    final valid = hands.where((h) => h.isValid).toList();
    if (requiredHands >= 2 && valid.length >= 2) {
      final sorted = List<HandPose>.from(valid)
        ..sort((a, b) => mirrorX
            ? b.wrist.x.compareTo(a.wrist.x)
            : a.wrist.x.compareTo(b.wrist.x));
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

    return dp[n][m] / ((n + m) / 2.0);
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

class _PreparedSignTemplate {
  final String word;
  final int requiredHands;
  final List<List<double>> directSequence;
  final List<List<double>> mirroredSequence;

  const _PreparedSignTemplate({
    required this.word,
    required this.requiredHands,
    required this.directSequence,
    required this.mirroredSequence,
  });
}
