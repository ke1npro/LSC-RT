import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/usecases/evaluate_recorded_sign_practice_usecase.dart';

void main() {
  group('EvaluateRecordedSignPracticeUseCase Tests', () {
    final useCase = EvaluateRecordedSignPracticeUseCase();

    List<LandmarkPoint> makeOpenHand({double offsetX = 0.5, double offsetY = 0.5}) {
      return List.generate(21, (i) {
        if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
        if (i == 9) return LandmarkPoint(x: offsetX, y: offsetY - 0.1);
        return LandmarkPoint(
          x: offsetX + ((i % 5) - 2) * 0.02,
          y: offsetY - 0.05 - (i * 0.008),
        );
      });
    }

    List<LandmarkPoint> makeFistHand({double offsetX = 0.5, double offsetY = 0.5}) {
      return List.generate(21, (i) {
        if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
        if (i == 9) return LandmarkPoint(x: offsetX, y: offsetY - 0.1);
        return LandmarkPoint(
          x: offsetX + ((i % 3) - 1) * 0.005,
          y: offsetY - 0.02,
        );
      });
    }

    RecordedSign makeReferenceSign({
      int frameCount = 20,
      int requiredHands = 1,
    }) {
      final frames = List.generate(frameCount, (i) {
        final t = i / (frameCount - 1);
        final hand1 = HandPose(
          landmarks: makeOpenHand(offsetX: 0.4 + t * 0.2, offsetY: 0.5 - t * 0.1),
        );
        final hands = requiredHands == 2
            ? [
                hand1,
                HandPose(
                  landmarks: makeOpenHand(offsetX: 0.7 - t * 0.1, offsetY: 0.5),
                ),
              ]
            : [hand1];
        return SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 33,
          hands: hands,
        );
      });

      return RecordedSign(
        id: 'ref_hola',
        word: 'HOLA',
        category: 'Saludos',
        requiredHands: requiredHands,
        fps: 30.0,
        detectionRate: 1.0,
        averageConfidence: 0.95,
        totalTakesEvaluated: 1,
        createdAt: DateTime(2026, 11, 13),
        frames: frames,
      );
    }

    test('Matching sequence at different speed yields mastered verdict (>= 75%)', () {
      final ref = makeReferenceSign(frameCount: 20);

      // Usuario ejecuta la misma seña pero más rápido (12 frames) y con pequeña variación
      final attempt = List.generate(12, (i) {
        final t = i / 11.0;
        return SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 33,
          hands: [
            HandPose(
              landmarks: makeOpenHand(offsetX: 0.35 + t * 0.2, offsetY: 0.52 - t * 0.1),
            ),
          ],
        );
      });

      final result = useCase.execute(referenceSign: ref, attemptFrames: attempt);

      expect(result.verdict, PracticeVerdict.mastered);
      expect(result.confidencePercent, greaterThanOrEqualTo(75));
      expect(result.handDetectionRate, closeTo(1.0, 0.01));
    });

    test('Auto-trims leading and trailing empty frames in 6s practice recording', () {
      final ref = makeReferenceSign(frameCount: 20);

      final attempt = [
        // 15 frames muertos al inicio (levantando la mano)
        ...List.generate(
          15,
          (i) => SignFrameLandmarks(frameIndex: i, timestampMs: i * 33, hands: const []),
        ),
        // 20 frames ejecutando la seña correctamente
        ...List.generate(20, (i) {
          final t = i / 19.0;
          return SignFrameLandmarks(
            frameIndex: 15 + i,
            timestampMs: (15 + i) * 33,
            hands: [
              HandPose(
                landmarks: makeOpenHand(offsetX: 0.4 + t * 0.2, offsetY: 0.5 - t * 0.1),
              ),
            ],
          );
        }),
        // 15 frames muertos al final (bajando la mano)
        ...List.generate(
          15,
          (i) => SignFrameLandmarks(
            frameIndex: 35 + i,
            timestampMs: (35 + i) * 33,
            hands: const [],
          ),
        ),
      ];

      final result = useCase.execute(referenceSign: ref, attemptFrames: attempt);

      expect(result.verdict, PracticeVerdict.mastered);
      expect(result.totalEvaluatedFrames, 20);
      expect(result.handDetectionRate, closeTo(1.0, 0.01));
    });

    test('Different handshape and static posture yields lower confidence than matching sign', () {
      final ref = makeReferenceSign(frameCount: 20);

      final wrongAttempt = List.generate(20, (i) {
        return SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 33,
          hands: [
            HandPose(landmarks: makeFistHand(offsetX: 0.8, offsetY: 0.8)),
          ],
        );
      });

      final result = useCase.execute(referenceSign: ref, attemptFrames: wrongAttempt);

      expect(result.confidencePercent, lessThan(75));
      expect(result.verdict, isNot(PracticeVerdict.mastered));
    });

    test('Returns insufficientHands when no hands are detected', () {
      final ref = makeReferenceSign(frameCount: 20);
      final emptyAttempt = List.generate(
        20,
        (i) => SignFrameLandmarks(frameIndex: i, timestampMs: i * 33, hands: const []),
      );

      final result = useCase.execute(referenceSign: ref, attemptFrames: emptyAttempt);

      expect(result.verdict, PracticeVerdict.insufficientHands);
      expect(result.confidencePercent, 0);
    });

    test('Bimanual reference requires 2 hands during practice', () {
      final refBimanual = makeReferenceSign(frameCount: 15, requiredHands: 2);
      final singleHandAttempt = List.generate(15, (i) {
        return SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 33,
          hands: [HandPose(landmarks: makeOpenHand())],
        );
      });

      final result = useCase.execute(
        referenceSign: refBimanual,
        attemptFrames: singleHandAttempt,
      );

      expect(result.verdict, PracticeVerdict.insufficientHands);
      expect(result.confidencePercent, 0);
    });
  });
}
