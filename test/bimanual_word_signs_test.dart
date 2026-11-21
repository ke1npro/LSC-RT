import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/entities/sign_prediction.dart';
import 'package:sign_language_app/domain/repositories/i_dictionary_repository.dart';
import 'package:sign_language_app/domain/usecases/recognize_dictionary_sign_usecase.dart';
import 'package:sign_language_app/domain/usecases/resolve_body_pose_usecase.dart';

class _FakeDictionaryRepository implements IDictionaryRepository {
  final List<RecordedSign> _signs = [];
  bool _loaded = true;

  @override
  List<RecordedSign> get allSigns => List.unmodifiable(_signs);

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> initialize() async {
    _loaded = true;
  }

  @override
  RecordedSign? getSignById(String id) {
    for (final s in _signs) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<void> saveRecordedSign(RecordedSign sign) async {
    _signs.removeWhere((s) => s.id == sign.id);
    _signs.add(sign);
  }

  @override
  Future<void> deleteRecordedSign(String id) async {
    _signs.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> clearAllSigns() async {
    _signs.clear();
  }

  @override
  Future<String> exportDictionaryJson() async => '[]';

  @override
  Future<int> importDictionaryJson(String jsonString) async => 0;
}

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

List<LandmarkPoint> _thumbsUpLandmarks({double offsetX = 0.5, double offsetY = 0.60}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
    if (i == 4) return LandmarkPoint(x: offsetX, y: offsetY - 0.35);
    if (i == 2) return LandmarkPoint(x: offsetX, y: offsetY - 0.20);
    if (i == 6 || i == 10 || i == 14 || i == 18) {
      return LandmarkPoint(x: offsetX, y: offsetY - 0.16);
    }
    return LandmarkPoint(x: offsetX, y: offsetY - 0.08);
  });
}

List<LandmarkPoint> _pointingIndexLandmarks({double offsetX = 0.5, double offsetY = 0.38}) {
  return List.generate(21, (i) {
    if (i == 0) return LandmarkPoint(x: offsetX, y: offsetY);
    if (i == 8) return LandmarkPoint(x: offsetX, y: offsetY + 0.14);
    if (i == 6) return LandmarkPoint(x: offsetX, y: offsetY + 0.07);
    if (i == 10 || i == 14 || i == 18) {
      return LandmarkPoint(x: offsetX, y: offsetY + 0.02);
    }
    return LandmarkPoint(x: offsetX, y: offsetY + 0.01);
  });
}

RecordedSign _buildRecordedSign({
  required String id,
  required String word,
  required int requiredHands,
  required List<LandmarkPoint> Function(double t) leftOrPrimaryGenerator,
  List<LandmarkPoint> Function(double t)? rightGenerator,
  int frameCount = 12,
}) {
  final frames = List.generate(frameCount, (i) {
    final t = frameCount > 1 ? i / (frameCount - 1) : 0.0;
    final hands = <HandPose>[
      HandPose(landmarks: leftOrPrimaryGenerator(t)),
    ];
    if (requiredHands >= 2 && rightGenerator != null) {
      hands.add(HandPose(landmarks: rightGenerator(t)));
    }
    return SignFrameLandmarks(
      frameIndex: i,
      timestampMs: i * 33,
      hands: hands,
    );
  });

  return RecordedSign(
    id: id,
    word: word,
    category: 'General',
    requiredHands: requiredHands,
    fps: 30.0,
    detectionRate: 1.0,
    averageConfidence: 0.95,
    totalTakesEvaluated: 1,
    createdAt: DateTime(2026, 11, 21),
    frames: frames,
  );
}

void main() {
  group('Bimanual & Dual Arm IK Resolution Tests', () {
    test('ResolveBodyPoseUseCase resolves both arms simultaneously when 2 hands are detected', () {
      final useCase = ResolveBodyPoseUseCase();
      final leftHand = HandPose(
        landmarks: List.generate(21, (i) => LandmarkPoint(x: 0.35, y: 0.50 + i * 0.005)),
      );
      final rightHand = HandPose(
        landmarks: List.generate(21, (i) => LandmarkPoint(x: 0.65, y: 0.50 + i * 0.005)),
      );

      final pose = useCase.execute(
        hands: [leftHand, rightHand],
        faces: [],
        logicalWidth: 400,
        logicalHeight: 800,
      );

      expect(pose.hands.length, equals(2));
      expect(pose.arms.length, equals(2));
      expect(pose.arms.any((a) => !a.isRightArm), isTrue,
          reason: 'Debe contener el brazo izquierdo');
      expect(pose.arms.any((a) => a.isRightArm), isTrue,
          reason: 'Debe contener el brazo derecho');
    });

    test('ResolveBodyPoseUseCase handles single hand transition with hysteresis', () {
      final useCase = ResolveBodyPoseUseCase();
      final rightHand = HandPose(
        landmarks: List.generate(21, (i) => LandmarkPoint(x: 0.70, y: 0.50 + i * 0.005)),
      );

      final pose = useCase.execute(
        hands: [rightHand],
        faces: [],
        logicalWidth: 400,
        logicalHeight: 800,
      );

      expect(pose.hands.length, equals(1));
      expect(pose.arms.length, equals(1));
      expect(pose.arms.first.isRightArm, isTrue);
    });
  });

  group('Dictionary-Based Sign Recognition Tests', () {
    test('Empty dictionary returns null even for former hardcoded gestures (BIEN / YO)', () {
      final repo = _FakeDictionaryRepository();
      final useCase = RecognizeDictionarySignUseCase(repo);

      for (int i = 0; i < 6; i++) {
        expect(
          useCase.execute(hands: [HandPose(landmarks: _thumbsUpLandmarks())]),
          isNull,
        );
      }

      for (int i = 0; i < 6; i++) {
        expect(
          useCase.execute(hands: [HandPose(landmarks: _pointingIndexLandmarks())]),
          isNull,
        );
      }
    });

    test('Recognizes a unimanual RecordedSign stored in the dictionary', () async {
      final repo = _FakeDictionaryRepository();
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'saludo_1',
          word: 'HOLA',
          requiredHands: 1,
          leftOrPrimaryGenerator: (t) => _openHandLandmarks(offsetX: 0.45 + t * 0.12),
        ),
      );

      final useCase = RecognizeDictionarySignUseCase(repo);
      SignPrediction? lastPred;
      for (int i = 0; i < 8; i++) {
        final t = i / 7.0;
        lastPred = useCase.execute(
          hands: [HandPose(landmarks: _openHandLandmarks(offsetX: 0.45 + t * 0.12))],
        );
      }

      expect(lastPred, isNotNull);
      expect(lastPred!.isRecognized, isTrue);
      expect(lastPred.label, equals('HOLA'));
      expect(lastPred.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Recognizes a bimanual RecordedSign stored in the dictionary when 2 hands are provided', () async {
      final repo = _FakeDictionaryRepository();
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'familia_1',
          word: 'FAMILIA',
          requiredHands: 2,
          leftOrPrimaryGenerator: (t) => _openHandLandmarks(offsetX: 0.35 - t * 0.05),
          rightGenerator: (t) => _openHandLandmarks(offsetX: 0.65 + t * 0.05),
        ),
      );

      final useCase = RecognizeDictionarySignUseCase(repo);
      SignPrediction? lastPred;
      for (int i = 0; i < 8; i++) {
        final t = i / 7.0;
        lastPred = useCase.execute(
          hands: [
            HandPose(landmarks: _openHandLandmarks(offsetX: 0.35 - t * 0.05)),
            HandPose(landmarks: _openHandLandmarks(offsetX: 0.65 + t * 0.05)),
          ],
        );
      }

      expect(lastPred, isNotNull);
      expect(lastPred!.isRecognized, isTrue);
      expect(lastPred.label, equals('FAMILIA'));
      expect(lastPred.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Distinguishes between two different unimanual signs in the dictionary', () async {
      final repo = _FakeDictionaryRepository();
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'abierta_1',
          word: 'ABIERTA',
          requiredHands: 1,
          leftOrPrimaryGenerator: (_) => _openHandLandmarks(),
        ),
      );
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'puno_1',
          word: 'PUÑO',
          requiredHands: 1,
          leftOrPrimaryGenerator: (_) => _fistLandmarks(),
        ),
      );

      final useCase = RecognizeDictionarySignUseCase(repo);
      SignPrediction? predOpen;
      for (int i = 0; i < 6; i++) {
        predOpen = useCase.execute(hands: [HandPose(landmarks: _openHandLandmarks())]);
      }
      expect(predOpen?.label, equals('ABIERTA'));

      useCase.reset();
      SignPrediction? predFist;
      for (int i = 0; i < 6; i++) {
        predFist = useCase.execute(hands: [HandPose(landmarks: _fistLandmarks())]);
      }
      expect(predFist?.label, equals('PUÑO'));
    });

    test('Rejects an unrelated gesture against recorded dictionary signs', () async {
      final repo = _FakeDictionaryRepository();
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'abierta_1',
          word: 'ABIERTA',
          requiredHands: 1,
          leftOrPrimaryGenerator: (_) => _openHandLandmarks(),
        ),
      );

      final useCase = RecognizeDictionarySignUseCase(repo);
      SignPrediction? pred;
      for (int i = 0; i < 8; i++) {
        pred = useCase.execute(hands: [HandPose(landmarks: _thumbsUpLandmarks())]);
      }

      expect(pred?.isRecognized ?? false, isFalse);
    });

    test('Recognizes a sign even when live X coordinates are horizontally mirrored', () async {
      final repo = _FakeDictionaryRepository();
      await repo.saveRecordedSign(
        _buildRecordedSign(
          id: 'saludo_espejo',
          word: 'SALUDO',
          requiredHands: 1,
          leftOrPrimaryGenerator: (t) => _openHandLandmarks(offsetX: 0.30 + t * 0.15),
        ),
      );

      final useCase = RecognizeDictionarySignUseCase(repo);
      SignPrediction? pred;
      for (int i = 0; i < 8; i++) {
        final t = i / 7.0;
        // Espejo horizontal (1.0 - x) de cada punto grabado
        final mirrored = _openHandLandmarks(offsetX: 0.30 + t * 0.15)
            .map((p) => LandmarkPoint(x: 1.0 - p.x, y: p.y, z: p.z))
            .toList();
        pred = useCase.execute(hands: [HandPose(landmarks: mirrored)]);
      }

      expect(pred, isNotNull);
      expect(pred!.isRecognized, isTrue);
      expect(pred.label, equals('SALUDO'));
    });
  });
}
