import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/entities/sign_take_candidate.dart';
import 'package:sign_language_app/domain/usecases/select_best_take_usecase.dart';

void main() {
  group('RecordedSign & SignTakeCandidate Entity Tests', () {
    List<LandmarkPoint> createDummyLandmarks() {
      return List.generate(
        21,
        (i) => LandmarkPoint(x: i * 0.04, y: 0.5, z: 0.0),
      );
    }

    HandPose createDummyHand({double confidence = 0.90, String handedness = 'Right'}) {
      return HandPose(
        landmarks: createDummyLandmarks(),
        confidence: confidence,
        handedness: handedness,
      );
    }

    test('SignFrameLandmarks evaluates validity for 1 and 2 hands', () {
      final frameWith1Hand = SignFrameLandmarks(
        frameIndex: 0,
        timestampMs: 0,
        hands: [createDummyHand()],
      );
      expect(frameWith1Hand.isValidFor(1), isTrue);
      expect(frameWith1Hand.isValidFor(2), isFalse);

      final frameWith2Hands = SignFrameLandmarks(
        frameIndex: 1,
        timestampMs: 33,
        hands: [
          createDummyHand(handedness: 'Right'),
          createDummyHand(handedness: 'Left'),
        ],
      );
      expect(frameWith2Hands.isValidFor(1), isTrue);
      expect(frameWith2Hands.isValidFor(2), isTrue);
    });

    test('SignTakeCandidate trims range and rebases timestamps starting at 0 ms', () {
      final frames = List.generate(10, (i) {
        return SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 33,
          hands: [createDummyHand()],
        );
      });

      final take = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/tmp/test.mp4',
        allFrames: frames,
        videoDurationMs: 330,
        trimStartFrame: 2,
        trimEndFrame: 6,
      );

      expect(take.trimmedFramesCount, 5);
      final trimmed = take.trimmedFrames;
      expect(trimmed.length, 5);
      expect(trimmed.first.frameIndex, 0);
      expect(trimmed.first.timestampMs, 0);
      expect(trimmed.last.frameIndex, 4);
      expect(trimmed.last.timestampMs, 4 * 33);
    });
  });

  group('SelectBestTakeUseCase Selection & Scoring Tests', () {
    List<LandmarkPoint> dummy21 = List.generate(
      21,
      (i) => LandmarkPoint(x: i * 0.01, y: 0.1, z: 0.0),
    );

    SignFrameLandmarks validFrame(int index, {double conf = 0.85}) {
      return SignFrameLandmarks(
        frameIndex: index,
        timestampMs: index * 33,
        hands: [HandPose(landmarks: dummy21, confidence: conf)],
      );
    }

    SignFrameLandmarks emptyFrame(int index) {
      return SignFrameLandmarks(
        frameIndex: index,
        timestampMs: index * 33,
        hands: const [],
      );
    }

    test('Selects take with 35/40 frames (87.5%) over take with 20/40 frames (50%)', () {
      // Toma 1: 35 frames válidos de 40 (87.5%)
      final framesTake1 = [
        ...List.generate(35, (i) => validFrame(i)),
        ...List.generate(5, (i) => emptyFrame(35 + i)),
      ];
      final take1 = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/tmp/t1.mp4',
        allFrames: framesTake1,
        videoDurationMs: 40 * 33,
      );

      // Toma 2: 20 frames válidos de 40 (50.0%)
      final framesTake2 = [
        ...List.generate(20, (i) => validFrame(i)),
        ...List.generate(20, (i) => emptyFrame(20 + i)),
      ];
      final take2 = SignTakeCandidate(
        takeNumber: 2,
        tempVideoPath: '/tmp/t2.mp4',
        allFrames: framesTake2,
        videoDurationMs: 40 * 33,
      );

      final useCase = SelectBestTakeUseCase();
      final result = useCase.execute(
        takes: [take2, take1], // orden aleatorio
        requiredHands: 1,
      );

      expect(result, isNotNull);
      expect(result!.winner.takeNumber, 1);
      expect(result.bestRate, closeTo(0.875, 0.001));
      expect(result.isAcceptable, isTrue);
    });

    test('Trimming dead frames increases detection score and can flip the winner', () {
      // Toma con frames vacíos al inicio (0..4) y fin (35..39), pero 100% válida entre 5..34
      final rawFrames = [
        ...List.generate(5, (i) => emptyFrame(i)),
        ...List.generate(30, (i) => validFrame(5 + i)),
        ...List.generate(5, (i) => emptyFrame(35 + i)),
      ];

      // Sin recortar: 30 / 40 = 75.0%
      final unclippedTake = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/tmp/t1.mp4',
        allFrames: rawFrames,
        videoDurationMs: 40 * 33,
        trimStartFrame: 0,
        trimEndFrame: 39,
      );
      expect(unclippedTake.detectionRate(1), closeTo(0.75, 0.01));

      // Recortada a [5, 34]: 30 / 30 = 100.0%
      final clippedTake = unclippedTake.copyWith(
        trimStartFrame: 5,
        trimEndFrame: 34,
      );
      expect(clippedTake.detectionRate(1), closeTo(1.0, 0.01));
    });

    test('Uses averageConfidence as tie-breaker when detection rates are equal', () {
      final framesHighConf = List.generate(20, (i) => validFrame(i, conf: 0.95));
      final framesLowConf = List.generate(20, (i) => validFrame(i, conf: 0.72));

      final takeA = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/tmp/ta.mp4',
        allFrames: framesLowConf,
        videoDurationMs: 20 * 33,
      );

      final takeB = SignTakeCandidate(
        takeNumber: 2,
        tempVideoPath: '/tmp/tb.mp4',
        allFrames: framesHighConf,
        videoDurationMs: 20 * 33,
      );

      final useCase = SelectBestTakeUseCase();
      final result = useCase.execute(
        takes: [takeA, takeB],
        requiredHands: 1,
      );

      expect(result, isNotNull);
      expect(result!.winner.takeNumber, 2); // Ganador takeB por mayor confianza media
      expect(result.bestConfidence, closeTo(0.95, 0.01));
    });

    test('Rejects when best sample is below 70% threshold', () {
      final framesPoor = [
        ...List.generate(15, (i) => validFrame(i)),
        ...List.generate(25, (i) => emptyFrame(15 + i)),
      ]; // 15 / 40 = 37.5%

      final take = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/tmp/poor.mp4',
        allFrames: framesPoor,
        videoDurationMs: 40 * 33,
      );

      final useCase = SelectBestTakeUseCase();
      final result = useCase.execute(
        takes: [take],
        requiredHands: 1,
      );

      expect(result, isNotNull);
      expect(result!.isAcceptable, isFalse);
      expect(result.bestRate, closeTo(0.375, 0.01));
    });
  });
}
