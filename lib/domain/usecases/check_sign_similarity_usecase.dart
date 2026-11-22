import 'dart:math' as math;
import '../entities/hand_pose.dart';
import '../entities/recorded_sign.dart';

class SimilarSignMatch {
  final RecordedSign existingSign;
  final double similarity; // 0.0 a 1.0

  const SimilarSignMatch({
    required this.existingSign,
    required this.similarity,
  });

  int get similarityPercent => (similarity * 100).round().clamp(0, 100);
}

class SignSimilarityReport {
  final List<SimilarSignMatch> matches;
  final double warningThreshold;
  final double duplicateThreshold;

  const SignSimilarityReport({
    required this.matches,
    this.warningThreshold = 0.82,
    this.duplicateThreshold = 0.90,
  });

  SimilarSignMatch? get closestMatch =>
      matches.isNotEmpty ? matches.first : null;

  bool get hasHighSimilarity =>
      closestMatch != null && closestMatch!.similarity >= warningThreshold;

  bool get isDuplicate =>
      closestMatch != null && closestMatch!.similarity >= duplicateThreshold;

  List<SimilarSignMatch> get highSimilarityMatches =>
      matches.where((m) => m.similarity >= warningThreshold).toList();
}

/// Compara una seña candidata contra las señas ya existentes en el diccionario
/// para alertar al usuario antes de guardar si hay duplicados o señas muy parecidas.
class CheckSignSimilarityUseCase {
  static const int _resampleSteps = 20;

  SignSimilarityReport execute({
    required List<SignFrameLandmarks> candidateFrames,
    required int requiredHands,
    required List<RecordedSign> existingSigns,
    double warningThreshold = 0.82,
    double duplicateThreshold = 0.90,
  }) {
    final normalizedHands = requiredHands >= 2 ? 2 : 1;
    final candidateValid =
        candidateFrames.where((f) => f.isValidFor(normalizedHands)).toList();

    if (candidateValid.isEmpty || existingSigns.isEmpty) {
      return SignSimilarityReport(
        matches: const [],
        warningThreshold: warningThreshold,
        duplicateThreshold: duplicateThreshold,
      );
    }

    final candidateSeq = _resampleSequence(
      _extractSequenceFeatures(candidateValid, normalizedHands, mirrorX: false),
      _resampleSteps,
    );

    if (candidateSeq.isEmpty) {
      return SignSimilarityReport(
        matches: const [],
        warningThreshold: warningThreshold,
        duplicateThreshold: duplicateThreshold,
      );
    }

    final matches = <SimilarSignMatch>[];

    for (final existing in existingSigns) {
      final existingHands = existing.requiredHands >= 2 ? 2 : 1;
      if (existingHands != normalizedHands) continue;

      final existingValid =
          existing.frames.where((f) => f.isValidFor(existingHands)).toList();
      if (existingValid.isEmpty) continue;

      final directSeq = _resampleSequence(
        _extractSequenceFeatures(existingValid, existingHands, mirrorX: false),
        _resampleSteps,
      );
      final mirroredSeq = _resampleSequence(
        _extractSequenceFeatures(existingValid, existingHands, mirrorX: true),
        _resampleSteps,
      );

      final directDist = _computeDtwMeanDistance(candidateSeq, directSeq);
      final mirroredDist = _computeDtwMeanDistance(candidateSeq, mirroredSeq);
      final bestDist = math.min(directDist, mirroredDist);
      final similarity = math.exp(-1.35 * bestDist).clamp(0.0, 1.0);

      matches.add(
        SimilarSignMatch(
          existingSign: existing,
          similarity: similarity,
        ),
      );
    }

    matches.sort((a, b) => b.similarity.compareTo(a.similarity));

    return SignSimilarityReport(
      matches: matches,
      warningThreshold: warningThreshold,
      duplicateThreshold: duplicateThreshold,
    );
  }

  List<List<double>> _extractSequenceFeatures(
    List<SignFrameLandmarks> frames,
    int requiredHands, {
    required bool mirrorX,
  }) {
    if (frames.isEmpty) return const [];

    final double xSign = mirrorX ? -1.0 : 1.0;
    final firstOrdered =
        _orderedHands(frames.first.hands, requiredHands, mirrorX: mirrorX);
    final baseWristX = firstOrdered.first.wrist.x;
    final baseWristY = firstOrdered.first.wrist.y;

    return frames.map((frame) {
      final ordered =
          _orderedHands(frame.hands, requiredHands, mirrorX: mirrorX);
      final features = <double>[];

      for (int h = 0; h < requiredHands; h++) {
        final hand = ordered[h];
        final wrist = hand.wrist;
        final middleBase = hand.middleBase;

        final dxScale = middleBase.x - wrist.x;
        final dyScale = middleBase.y - wrist.y;
        final rawScale = math.sqrt(dxScale * dxScale + dyScale * dyScale);
        final scale = rawScale > 0.005 ? rawScale : 1.0;

        for (int i = 0; i < 21; i++) {
          final pt = hand.landmarks[i];
          features.add(((pt.x - wrist.x) / scale) * xSign);
          features.add((pt.y - wrist.y) / scale);
        }

        features.add(((wrist.x - baseWristX) * 1.4) * xSign);
        features.add((wrist.y - baseWristY) * 1.4);
      }

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
