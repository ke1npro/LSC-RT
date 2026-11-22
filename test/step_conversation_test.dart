import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/usecases/compose_avatar_response_usecase.dart';
import 'package:sign_language_app/domain/usecases/segment_and_translate_video_usecase.dart';

List<LandmarkPoint> _openHandAt({double x = 0.5, double y = 0.55}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: x, y: y);
    if (i == 9) return LandmarkPoint(x: x, y: y - 0.10);
    return LandmarkPoint(
      x: x + ((i % 5) - 2) * 0.025,
      y: y - 0.06 - (i * 0.008),
    );
  });
}

List<LandmarkPoint> _fistAt({double x = 0.5, double y = 0.55}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: x, y: y);
    if (i == 9) return LandmarkPoint(x: x, y: y - 0.09);
    return LandmarkPoint(
      x: x + ((i % 3) - 1) * 0.004,
      y: y - 0.015,
    );
  });
}

List<LandmarkPoint> _thumbsUpAt({double x = 0.5, double y = 0.60}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: x, y: y);
    if (i == 4) return LandmarkPoint(x: x, y: y - 0.35);
    if (i == 2) return LandmarkPoint(x: x, y: y - 0.20);
    if (i == 6 || i == 10 || i == 14 || i == 18) {
      return LandmarkPoint(x: x, y: y - 0.16);
    }
    return LandmarkPoint(x: x, y: y - 0.08);
  });
}

List<SignFrameLandmarks> _buildFrames(
  int count,
  List<LandmarkPoint> Function(double t) generator, {
  int startIndex = 0,
}) {
  return List.generate(count, (i) {
    final t = count > 1 ? i / (count - 1) : 0.0;
    final idx = startIndex + i;
    return SignFrameLandmarks(
      frameIndex: idx,
      timestampMs: idx * 33,
      hands: [HandPose(landmarks: generator(t))],
    );
  });
}

RecordedSign _makeRecordedSign({
  required String id,
  required String word,
  required List<SignFrameLandmarks> frames,
}) {
  return RecordedSign(
    id: id,
    word: word,
    category: 'General',
    requiredHands: 1,
    fps: 30.0,
    detectionRate: 1.0,
    averageConfidence: 0.95,
    totalTakesEvaluated: 1,
    createdAt: DateTime(2026, 11, 22),
    frames: frames,
  );
}

void main() {
  group('SegmentAndTranslateVideoUseCase (30 FPS Endpoint Spotting)', () {
    final useCase = SegmentAndTranslateVideoUseCase();

    test('Segments and translates 2 consecutive signs without pauses chronologically', () {
      final openFrames = _buildFrames(16, (t) => _openHandAt(x: 0.40 + t * 0.14));
      final fistFrames = _buildFrames(16, (t) => _fistAt(x: 0.55 - t * 0.10));

      final dict = [
        _makeRecordedSign(id: 'open_1', word: 'HOLA', frames: openFrames),
        _makeRecordedSign(id: 'fist_1', word: 'PUÑO', frames: fistFrames),
      ];

      // Grabación continua a 30 FPS sin pausas entre HOLA y PUÑO
      final continuousRecording = [
        ..._buildFrames(16, (t) => _openHandAt(x: 0.40 + t * 0.14), startIndex: 0),
        ..._buildFrames(16, (t) => _fistAt(x: 0.55 - t * 0.10), startIndex: 16),
      ];

      final result = useCase.execute(
        recordedFrames: continuousRecording,
        dictionarySigns: dict,
      );

      expect(result.hasTranslation, isTrue);
      expect(result.segments.length, 2);
      expect(result.segments[0].word, equals('HOLA'));
      expect(result.segments[1].word, equals('PUÑO'));
      expect(result.fullText, equals('HOLA PUÑO'));
    });

    test('Translates a single-sign recording cleanly', () {
      final frames = _buildFrames(18, (t) => _openHandAt(x: 0.45 + t * 0.1));
      final dict = [
        _makeRecordedSign(id: 'hola_1', word: 'HOLA', frames: frames),
      ];

      final result = useCase.execute(
        recordedFrames: frames,
        dictionarySigns: dict,
      );

      expect(result.hasTranslation, isTrue);
      expect(result.segments.single.word, equals('HOLA'));
      expect(result.segments.single.confidence, greaterThanOrEqualTo(0.85));
    });

    test('Returns empty translation when dictionary is empty or no sign matches', () {
      final openFrames = _buildFrames(16, (_) => _openHandAt());
      final emptyResult = useCase.execute(
        recordedFrames: openFrames,
        dictionarySigns: const [],
      );
      expect(emptyResult.hasTranslation, isFalse);

      final dict = [
        _makeRecordedSign(id: 'open_1', word: 'HOLA', frames: openFrames),
      ];
      final unrelated = _buildFrames(16, (_) => _thumbsUpAt());
      final noMatchResult = useCase.execute(
        recordedFrames: unrelated,
        dictionarySigns: dict,
      );
      expect(noMatchResult.hasTranslation, isFalse);
    });
  });

  group('ComposeAvatarResponseUseCase Tests', () {
    final useCase = ComposeAvatarResponseUseCase();

    test('Matches multi-word phrases via greedy longest-match and ignores accents/punctuation', () {
      final buenosDias = _makeRecordedSign(
        id: 'bd_1',
        word: 'BUENOS DIAS',
        frames: _buildFrames(10, (t) => _openHandAt(x: 0.4 + t * 0.1)),
      );
      final gracias = _makeRecordedSign(
        id: 'gr_1',
        word: 'GRACIAS',
        frames: _buildFrames(12, (_) => _fistAt()),
      );
      final buenosSolo = _makeRecordedSign(
        id: 'buenos_1',
        word: 'BUENOS',
        frames: _buildFrames(6, (_) => _thumbsUpAt()),
      );

      final response = useCase.execute(
        text: '¡Buenos días, gracias!',
        dictionarySigns: [buenosSolo, buenosDias, gracias],
        transitionFrames: 8,
      );

      expect(response.matchedSigns.map((s) => s.word).toList(),
          equals(['BUENOS DIAS', 'GRACIAS']));
      expect(response.missingWords, isEmpty);
      // 10 frames (BUENOS DIAS) + 8 transición Hermite + 12 frames (GRACIAS) = 30 frames
      expect(response.frames.length, 30);
      expect(response.wordStartFrames, equals([0, 18]));
    });

    test('Synthesizes smooth Hermite transitions and reports missing words without failing', () {
      final hola = _makeRecordedSign(
        id: 'hola_1',
        word: 'HOLA',
        frames: _buildFrames(8, (_) => _openHandAt(x: 0.2)),
      );
      final gracias = _makeRecordedSign(
        id: 'gr_1',
        word: 'GRACIAS',
        frames: _buildFrames(8, (_) => _openHandAt(x: 0.8)),
      );

      final response = useCase.execute(
        text: 'Hola amigo gracias mañana',
        dictionarySigns: [hola, gracias],
        transitionFrames: 8,
      );

      expect(response.hasAnimation, isTrue);
      expect(response.matchedSigns.map((s) => s.word).toList(),
          equals(['HOLA', 'GRACIAS']));
      expect(response.missingWords, equals(['amigo', 'mañana']));
      expect(response.frames.length, 8 + 8 + 8);

      // Comprobar que el frame intermedio de transición interpola X entre 0.2 y 0.8
      final midTransitionWristX = response.frames[11].hands.first.wrist.x;
      expect(midTransitionWristX, greaterThan(0.25));
      expect(midTransitionWristX, lessThan(0.75));
    });
  });
}
