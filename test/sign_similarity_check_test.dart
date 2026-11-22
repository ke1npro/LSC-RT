import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/usecases/check_sign_similarity_usecase.dart';

List<LandmarkPoint> _openHandLandmarks({double offsetX = 0.5, double offsetY = 0.55}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
    if (i == 9) return LandmarkPoint(x: offsetX, y: offsetY - 0.10);
    return LandmarkPoint(
      x: offsetX + ((i % 5) - 2) * 0.025,
      y: offsetY - 0.06 - (i * 0.008),
    );
  });
}

List<LandmarkPoint> _fistLandmarks({double offsetX = 0.5, double offsetY = 0.55}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
    if (i == 9) return LandmarkPoint(x: offsetX, y: offsetY - 0.09);
    return LandmarkPoint(
      x: offsetX + ((i % 3) - 1) * 0.004,
      y: offsetY - 0.015,
    );
  });
}

List<SignFrameLandmarks> _buildFrames({
  required int count,
  required List<LandmarkPoint> Function(double t) primaryGenerator,
  List<LandmarkPoint> Function(double t)? secondaryGenerator,
}) {
  return List.generate(count, (i) {
    final t = count > 1 ? i / (count - 1) : 0.0;
    final hands = <HandPose>[HandPose(landmarks: primaryGenerator(t))];
    if (secondaryGenerator != null) {
      hands.add(HandPose(landmarks: secondaryGenerator(t)));
    }
    return SignFrameLandmarks(
      frameIndex: i,
      timestampMs: i * 33,
      hands: hands,
    );
  });
}

RecordedSign _makeSign({
  required String id,
  required String word,
  required int requiredHands,
  required List<SignFrameLandmarks> frames,
}) {
  return RecordedSign(
    id: id,
    word: word,
    category: 'General',
    requiredHands: requiredHands,
    fps: 30.0,
    detectionRate: 1.0,
    averageConfidence: 0.95,
    totalTakesEvaluated: 1,
    createdAt: DateTime(2026, 11, 22),
    frames: frames,
  );
}

void main() {
  group('CheckSignSimilarityUseCase Tests', () {
    final useCase = CheckSignSimilarityUseCase();

    test('Returns empty report when dictionary has no signs', () {
      final candidate = _buildFrames(
        count: 15,
        primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.4 + t * 0.1),
      );

      final report = useCase.execute(
        candidateFrames: candidate,
        requiredHands: 1,
        existingSigns: const [],
      );

      expect(report.matches, isEmpty);
      expect(report.closestMatch, isNull);
      expect(report.hasHighSimilarity, isFalse);
      expect(report.isDuplicate, isFalse);
    });

    test('Flags identical recorded sign as duplicate (>= 90%)', () {
      final frames = _buildFrames(
        count: 20,
        primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.4 + t * 0.15),
      );
      final existing = _makeSign(
        id: 'hola_1',
        word: 'HOLA',
        requiredHands: 1,
        frames: frames,
      );

      final report = useCase.execute(
        candidateFrames: frames,
        requiredHands: 1,
        existingSigns: [existing],
      );

      expect(report.closestMatch, isNotNull);
      expect(report.closestMatch!.similarityPercent, greaterThanOrEqualTo(90));
      expect(report.isDuplicate, isTrue);
      expect(report.hasHighSimilarity, isTrue);
    });

    test('Detects very similar sign performed at a different speed', () {
      final existingFrames = _buildFrames(
        count: 24,
        primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.4 + t * 0.12),
      );
      final fasterCandidate = _buildFrames(
        count: 12,
        primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.41 + t * 0.12),
      );

      final existing = _makeSign(
        id: 'saludo_1',
        word: 'BUENAS',
        requiredHands: 1,
        frames: existingFrames,
      );

      final report = useCase.execute(
        candidateFrames: fasterCandidate,
        requiredHands: 1,
        existingSigns: [existing],
      );

      expect(report.hasHighSimilarity, isTrue);
      expect(report.closestMatch!.similarity, greaterThanOrEqualTo(0.82));
    });

    test('Does not flag clearly distinct handshape as similar', () {
      final existingOpen = _makeSign(
        id: 'open_1',
        word: 'HOLA',
        requiredHands: 1,
        frames: _buildFrames(
          count: 16,
          primaryGenerator: (_) => _openHandLandmarks(),
        ),
      );
      final candidateFist = _buildFrames(
        count: 16,
        primaryGenerator: (_) => _fistLandmarks(),
      );

      final report = useCase.execute(
        candidateFrames: candidateFist,
        requiredHands: 1,
        existingSigns: [existingOpen],
      );

      expect(report.hasHighSimilarity, isFalse);
      expect(report.isDuplicate, isFalse);
      expect(report.closestMatch!.similarity, lessThan(0.82));
    });

    test('Does not compare signs with different requiredHands (1 vs 2)', () {
      final existingBimanual = _makeSign(
        id: 'familia_1',
        word: 'FAMILIA',
        requiredHands: 2,
        frames: _buildFrames(
          count: 16,
          primaryGenerator: (_) => _openHandLandmarks(offsetX: 0.35),
          secondaryGenerator: (_) => _openHandLandmarks(offsetX: 0.65),
        ),
      );

      final candidateUnimanual = _buildFrames(
        count: 16,
        primaryGenerator: (_) => _openHandLandmarks(offsetX: 0.35),
      );

      final report = useCase.execute(
        candidateFrames: candidateUnimanual,
        requiredHands: 1,
        existingSigns: [existingBimanual],
      );

      expect(report.matches, isEmpty);
      expect(report.hasHighSimilarity, isFalse);
    });

    test('Sorts multiple matches descending with closest sign first', () {
      final fistSign = _makeSign(
        id: 'puno_1',
        word: 'PUÑO',
        requiredHands: 1,
        frames: _buildFrames(
          count: 15,
          primaryGenerator: (_) => _fistLandmarks(),
        ),
      );
      final openSign = _makeSign(
        id: 'abierta_1',
        word: 'ABIERTA',
        requiredHands: 1,
        frames: _buildFrames(
          count: 15,
          primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.45 + t * 0.1),
        ),
      );

      final candidate = _buildFrames(
        count: 15,
        primaryGenerator: (t) => _openHandLandmarks(offsetX: 0.45 + t * 0.1),
      );

      final report = useCase.execute(
        candidateFrames: candidate,
        requiredHands: 1,
        existingSigns: [fistSign, openSign],
      );

      expect(report.matches.length, 2);
      expect(report.closestMatch!.existingSign.word, equals('ABIERTA'));
      expect(
        report.matches[0].similarity,
        greaterThan(report.matches[1].similarity),
      );
    });
  });
}
