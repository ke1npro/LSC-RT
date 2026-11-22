import 'dart:math' as math;
import '../entities/conversation_turn.dart';
import '../entities/hand_pose.dart';
import '../entities/recorded_sign.dart';

class VideoTranslationResult {
  final List<TranslatedSignSegment> segments;
  final int totalFrames;
  final int validHandFrames;

  const VideoTranslationResult({
    required this.segments,
    required this.totalFrames,
    required this.validHandFrames,
  });

  String get fullText => segments.map((s) => s.word).join(' ');
  bool get hasTranslation => segments.isNotEmpty;
}

/// Segmenta y traduce automáticamente una secuencia de video procesada a 30 FPS
/// mediante **Endpoint-Spotted Continuous DTW** contra las señas del diccionario.
///
/// No exige pausas artificiales entre señas: detecta los fotogramas candidatos a
/// "punto final" de cada seña, evalúa ventanas retrospectivas proporcionales y
/// resuelve solapamientos cronológicamente con Non-Maximum Suppression (NMS).
class SegmentAndTranslateVideoUseCase {
  static const int _resampleSteps = 16;

  VideoTranslationResult execute({
    required List<SignFrameLandmarks> recordedFrames,
    required List<RecordedSign> dictionarySigns,
    double recognitionThreshold = 0.62,
    double endpointThreshold = 0.65,
  }) {
    if (recordedFrames.isEmpty) {
      return const VideoTranslationResult(
        segments: [],
        totalFrames: 0,
        validHandFrames: 0,
      );
    }

    final validHandFramesCount =
        recordedFrames.where((f) => f.hands.any((h) => h.isValid)).length;

    if (dictionarySigns.isEmpty || validHandFramesCount < 4) {
      return VideoTranslationResult(
        segments: const [],
        totalFrames: recordedFrames.length,
        validHandFrames: validHandFramesCount,
      );
    }

    final templates = _prepareTemplates(dictionarySigns);
    if (templates.isEmpty) {
      return VideoTranslationResult(
        segments: const [],
        totalFrames: recordedFrames.length,
        validHandFrames: validHandFramesCount,
      );
    }

    // Encontrar último frame con mano válida para evaluarlo obligatoriamente
    final lastValidIdx =
        recordedFrames.lastIndexWhere((f) => f.hands.any((h) => h.isValid));
    if (lastValidIdx < 0) {
      return VideoTranslationResult(
        segments: const [],
        totalFrames: recordedFrames.length,
        validHandFrames: 0,
      );
    }

    final candidates = <TranslatedSignSegment>[];
    final scanStep = recordedFrames.length > 90 ? 2 : 1;
    const lengthMultipliers = [0.65, 1.0, 1.4];

    for (int endIdx = 3; endIdx < recordedFrames.length; endIdx += scanStep) {
      _evaluateEndpointFrame(
        endIdx: endIdx,
        isForcedEndpoint: endIdx == lastValidIdx,
        recordedFrames: recordedFrames,
        templates: templates,
        endpointThreshold: endpointThreshold,
        recognitionThreshold: recognitionThreshold,
        lengthMultipliers: lengthMultipliers,
        outCandidates: candidates,
      );
    }

    // Asegurar evaluación exacta del último fotograma con mano válida si scanStep == 2 lo saltó
    if (lastValidIdx >= 3 && (lastValidIdx - 3) % scanStep != 0) {
      _evaluateEndpointFrame(
        endIdx: lastValidIdx,
        isForcedEndpoint: true,
        recordedFrames: recordedFrames,
        templates: templates,
        endpointThreshold: endpointThreshold,
        recognitionThreshold: recognitionThreshold,
        lengthMultipliers: lengthMultipliers,
        outCandidates: candidates,
      );
    }

    final selected = _applyTemporalNms(candidates);
    return VideoTranslationResult(
      segments: selected,
      totalFrames: recordedFrames.length,
      validHandFrames: validHandFramesCount,
    );
  }

  void _evaluateEndpointFrame({
    required int endIdx,
    required bool isForcedEndpoint,
    required List<SignFrameLandmarks> recordedFrames,
    required List<_EndpointSignTemplate> templates,
    required double endpointThreshold,
    required double recognitionThreshold,
    required List<double> lengthMultipliers,
    required List<TranslatedSignSegment> outCandidates,
  }) {
    final endFrame = recordedFrames[endIdx];
    final validEndHands = endFrame.hands.where((h) => h.isValid).toList();
    if (validEndHands.isEmpty) return;

    final activeHands = validEndHands.length >= 2 ? 2 : 1;
    final frameEndpointDirect =
        _extractStaticHandshape(validEndHands, activeHands, mirrorX: false);
    if (frameEndpointDirect.isEmpty) return;

    for (final template in templates) {
      if (template.requiredHands != activeHands) continue;

      final epDirectDist =
          _vectorDistance(frameEndpointDirect, template.endpointDirect);
      final epMirroredDist =
          _vectorDistance(frameEndpointDirect, template.endpointMirrored);
      final epSim = math.exp(-1.2 * math.min(epDirectDist, epMirroredDist));

      if (!isForcedEndpoint && epSim < endpointThreshold) continue;

      double bestSim = 0.0;
      int bestStartIdx = -1;

      for (final mult in lengthMultipliers) {
        final winLen = math.max(4, (template.refLength * mult).round());
        final startIdx = math.max(0, endIdx - winLen + 1);
        final windowSlice = recordedFrames
            .sublist(startIdx, endIdx + 1)
            .where((f) => f.isValidFor(activeHands))
            .toList();

        if (windowSlice.length < 4) continue;

        final queryRaw = _extractSequenceFeatures(
          windowSlice,
          activeHands,
          mirrorX: false,
        );
        if (queryRaw.isEmpty) continue;
        final querySeq = _resampleSequence(queryRaw, _resampleSteps);

        final directDist =
            _computeDtwMeanDistance(querySeq, template.directSequence);
        final mirroredDist =
            _computeDtwMeanDistance(querySeq, template.mirroredSequence) * 1.06;
        final effectiveDist = math.min(directDist, mirroredDist);
        final sim = math.exp(-1.30 * effectiveDist).clamp(0.0, 1.0);

        if (sim > bestSim) {
          bestSim = sim;
          bestStartIdx = startIdx;
        }
      }

      if (bestSim >= recognitionThreshold && bestStartIdx >= 0) {
        outCandidates.add(
          TranslatedSignSegment(
            word: template.word,
            startFrame: bestStartIdx,
            endFrame: endIdx,
            startMs: recordedFrames[bestStartIdx].timestampMs,
            endMs: recordedFrames[endIdx].timestampMs,
            confidence: bestSim,
          ),
        );
      }
    }
  }

  List<TranslatedSignSegment> _applyTemporalNms(
    List<TranslatedSignSegment> candidates,
  ) {
    if (candidates.isEmpty) return const [];

    final sorted = List<TranslatedSignSegment>.from(candidates)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <TranslatedSignSegment>[];
    for (final candidate in sorted) {
      final overlapsExisting = kept.any((existing) {
        final overlapStart = math.max(candidate.startFrame, existing.startFrame);
        final overlapEnd = math.min(candidate.endFrame, existing.endFrame);
        if (overlapEnd < overlapStart) return false;
        final overlapLen = (overlapEnd - overlapStart + 1).toDouble();
        final candLen = (candidate.endFrame - candidate.startFrame + 1).toDouble();
        final existLen = (existing.endFrame - existing.startFrame + 1).toDouble();
        final shorter = math.min(candLen, existLen);
        return (overlapLen / shorter) >= 0.35;
      });

      if (!overlapsExisting) {
        kept.add(candidate);
      }
    }

    kept.sort((a, b) => a.startFrame.compareTo(b.startFrame));
    return kept;
  }

  List<_EndpointSignTemplate> _prepareTemplates(List<RecordedSign> signs) {
    final result = <_EndpointSignTemplate>[];

    for (final sign in signs) {
      final reqHands = sign.requiredHands >= 2 ? 2 : 1;
      final validFrames =
          sign.frames.where((f) => f.isValidFor(reqHands)).toList();
      if (validFrames.isEmpty) continue;

      final directRaw =
          _extractSequenceFeatures(validFrames, reqHands, mirrorX: false);
      final mirroredRaw =
          _extractSequenceFeatures(validFrames, reqHands, mirrorX: true);
      if (directRaw.isEmpty || mirroredRaw.isEmpty) continue;

      final tailCount = math.min(3, validFrames.length);
      final tailFrames = validFrames.sublist(validFrames.length - tailCount);

      final epDirect = _averageStaticVectors(
        tailFrames
            .map((f) => _extractStaticHandshape(f.hands, reqHands, mirrorX: false))
            .where((v) => v.isNotEmpty)
            .toList(),
      );
      final epMirrored = _averageStaticVectors(
        tailFrames
            .map((f) => _extractStaticHandshape(f.hands, reqHands, mirrorX: true))
            .where((v) => v.isNotEmpty)
            .toList(),
      );

      if (epDirect.isEmpty || epMirrored.isEmpty) continue;

      result.add(
        _EndpointSignTemplate(
          word: sign.word,
          requiredHands: reqHands,
          refLength: validFrames.length.clamp(6, 180),
          directSequence: _resampleSequence(directRaw, _resampleSteps),
          mirroredSequence: _resampleSequence(mirroredRaw, _resampleSteps),
          endpointDirect: epDirect,
          endpointMirrored: epMirrored,
        ),
      );
    }

    return result;
  }

  List<double> _extractStaticHandshape(
    List<HandPose> hands,
    int requiredHands, {
    required bool mirrorX,
  }) {
    final valid = hands.where((h) => h.isValid).toList();
    if (valid.length < requiredHands) return const [];

    final xSign = mirrorX ? -1.0 : 1.0;
    final ordered = _orderedHands(valid, requiredHands, mirrorX: mirrorX);
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
    }

    return features;
  }

  List<double> _averageStaticVectors(List<List<double>> vectors) {
    if (vectors.isEmpty) return const [];
    final dim = vectors.first.length;
    final avg = List<double>.filled(dim, 0.0);
    for (final v in vectors) {
      if (v.length != dim) continue;
      for (int d = 0; d < dim; d++) {
        avg[d] += v[d];
      }
    }
    final count = vectors.length.toDouble();
    for (int d = 0; d < dim; d++) {
      avg[d] /= count;
    }
    return avg;
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
        final cost = _vectorDistance(seqA[i - 1], seqB[j - 1]);
        final bestPrev = math.min(
          dp[i - 1][j],
          math.min(dp[i][j - 1], dp[i - 1][j - 1]),
        );
        dp[i][j] = cost + bestPrev;
      }
    }

    return dp[n][m] / ((n + m) / 2.0);
  }

  double _vectorDistance(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 10.0;
    double sumSq = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sumSq += diff * diff;
    }
    return math.sqrt(sumSq / a.length);
  }
}

class _EndpointSignTemplate {
  final String word;
  final int requiredHands;
  final int refLength;
  final List<List<double>> directSequence;
  final List<List<double>> mirroredSequence;
  final List<double> endpointDirect;
  final List<double> endpointMirrored;

  const _EndpointSignTemplate({
    required this.word,
    required this.requiredHands,
    required this.refLength,
    required this.directSequence,
    required this.mirroredSequence,
    required this.endpointDirect,
    required this.endpointMirrored,
  });
}
