import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language_app/data/datasources/avatar_motion_datasource.dart';
import 'package:sign_language_app/data/datasources/local_storage_datasource.dart';
import 'package:sign_language_app/data/repositories/sign_repository_impl.dart';
import 'package:sign_language_app/domain/entities/avatar_sign_data.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/body_pose.dart';
import 'package:sign_language_app/domain/usecases/evaluate_posture_usecase.dart';
import 'package:sign_language_app/presentation/viewmodels/avatar_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Avatar Domain & Motion Synthesizer Tests', () {
    test('AvatarSignData and AvatarFrame model serialization', () {
      final signData = AvatarSignData(
        id: 'FAMILIA',
        signId: 'FAMILIA',
        displayName: 'FAMILIA',
        category: 'Familia',
        type: 'BIMANUAL',
        totalFrames: 10,
        fps: 24.0,
        durationSeconds: 0.41,
        apexFrame: 5,
        pedagogicalMetadata: const PedagogicalMetadata(
          description: 'Seña de familia.',
          instructions: 'Une los dedos índice y pulgar en forma de F.',
          handshapeDescription: 'Configuración F.',
          movementDescription: 'Círculo hacia el exterior.',
          locationDescription: 'Frente al pecho.',
        ),
        frames: [
          AvatarFrame(
            pose: {
              'nose': const AvatarPoint(0.5, 0.2),
              'left_shoulder': const AvatarPoint(0.35, 0.35),
              'right_shoulder': const AvatarPoint(0.65, 0.35),
            },
            rightHand: List.generate(21, (i) => AvatarPoint(0.5 + i * 0.01, 0.5)),
            leftHand: List.generate(21, (i) => AvatarPoint(0.5 - i * 0.01, 0.5)),
            hasLeftHand: true,
            hasRightHand: true,
          ),
        ],
      );

      expect(signData.id, 'FAMILIA');
      expect(signData.isBimanual, isTrue);
      expect(signData.frames.length, 1);
      expect(signData.frames.first.hasRightHand, isTrue);
    });

    test('AvatarMotionDataSource blends frames with Cubic Hermite smoothing', () {
      final ds = AvatarMotionDataSource();
      final sign1 = AvatarSignData(
        id: 'HOLA',
        signId: 'HOLA',
        displayName: 'HOLA',
        category: 'Saludos',
        type: 'UNIMANUAL',
        totalFrames: 5,
        fps: 24.0,
        durationSeconds: 0.2,
        apexFrame: 2,
        pedagogicalMetadata: const PedagogicalMetadata(
          description: '', instructions: '', handshapeDescription: '', movementDescription: '', locationDescription: '',
        ),
        frames: List.generate(
          5,
          (i) => AvatarFrame(
            pose: {'nose': AvatarPoint(0.5, 0.2 + i * 0.01)},
            hasLeftHand: false,
            hasRightHand: false,
          ),
        ),
      );

      final sign2 = AvatarSignData(
        id: 'GRACIAS',
        signId: 'GRACIAS',
        displayName: 'GRACIAS',
        category: 'Cortesía',
        type: 'UNIMANUAL',
        totalFrames: 5,
        fps: 24.0,
        durationSeconds: 0.2,
        apexFrame: 2,
        pedagogicalMetadata: const PedagogicalMetadata(
          description: '', instructions: '', handshapeDescription: '', movementDescription: '', locationDescription: '',
        ),
        frames: List.generate(
          5,
          (i) => AvatarFrame(
            pose: {'nose': AvatarPoint(0.5, 0.4 + i * 0.01)},
            hasLeftHand: false,
            hasRightHand: false,
          ),
        ),
      );

      final sequence = [sign1, sign2];
      final synthesized = ds.synthesizeSentence(sequence);

      // 5 frames (sign1) + 8 frames (Hermite blend) + 5 frames (sign2) = 18 frames
      expect(synthesized.length, 18);
      // El fotograma inicial de la transición debe estar cerca de sign1.last
      expect(synthesized[5].pose['nose']!.y, greaterThan(0.24));
      // El fotograma final de la transición debe estar cerca de sign2.first
      expect(synthesized[12].pose['nose']!.y, lessThan(0.41));
    });
  });

  group('AvatarViewModel Sentence Composer Tests', () {
    test('Sequence builder adds, removes, clears words and tracks active word index', () {
      final ds = AvatarMotionDataSource();
      final vm = AvatarViewModel(ds);

      final signA = AvatarSignData(
        id: 'A',
        signId: 'A',
        displayName: 'A',
        category: 'Abecedario',
        type: 'UNIMANUAL',
        totalFrames: 10,
        fps: 24.0,
        durationSeconds: 0.4,
        apexFrame: 5,
        pedagogicalMetadata: const PedagogicalMetadata(
          description: '', instructions: '', handshapeDescription: '', movementDescription: '', locationDescription: '',
        ),
        frames: List.generate(
          10,
          (_) => const AvatarFrame(pose: {}, hasLeftHand: false, hasRightHand: false),
        ),
      );

      final signB = AvatarSignData(
        id: 'B',
        signId: 'B',
        displayName: 'B',
        category: 'Abecedario',
        type: 'UNIMANUAL',
        totalFrames: 10,
        fps: 24.0,
        durationSeconds: 0.4,
        apexFrame: 5,
        pedagogicalMetadata: const PedagogicalMetadata(
          description: '', instructions: '', handshapeDescription: '', movementDescription: '', locationDescription: '',
        ),
        frames: List.generate(
          10,
          (_) => const AvatarFrame(pose: {}, hasLeftHand: false, hasRightHand: false),
        ),
      );

      vm.addWordToSentence(signA);
      vm.addWordToSentence(signB);

      expect(vm.sentenceSequence.length, 2);
      expect(vm.totalFrames, 28); // 10 + 8 transition + 10 = 28

      // Al inicio el frame 0 corresponde a signA ('A')
      expect(vm.currentWordDisplayName, 'A');

      // Buscar al frame 20 (segunda palabra)
      vm.seekToFrame(20);
      expect(vm.currentWordDisplayName, 'B');

      // Eliminar palabra en índice 1
      vm.removeWordAt(1);
      expect(vm.sentenceSequence.length, 1);
      expect(vm.sentenceSequence.first.id, 'A');

      // Limpiar todo
      vm.clearSentence();
      expect(vm.sentenceSequence.isEmpty, isTrue);
      expect(vm.totalFrames, 0);
    });
  });

  group('Posture Evaluation with Reference Canonical Frames Tests', () {
    test('EvaluatePostureUseCase computes normalized distance matching', () {
      final evaluator = EvaluatePostureUseCase();

      final refPoints = List.generate(
        21,
        (i) => AvatarPoint(0.5 + i * 0.01, 0.5 + i * 0.01),
      );
      final refFrame = AvatarFrame(
        pose: {},
        rightHand: refPoints,
        hasLeftHand: false,
        hasRightHand: true,
      );

      final userLandmarks = List.generate(
        21,
        (i) => LandmarkPoint(x: 0.5 + i * 0.01, y: 0.5 + i * 0.01),
      );
      final userHand = HandPose(landmarks: userLandmarks);
      final userPose = BodyPose(
        hands: [userHand],
      );

      final perfectScore = evaluator.execute(
        userPose: userPose,
        referenceFrame: refFrame,
        animationProgress: 0.0,
      );

      // Coincidencia idéntica produce puntuación cercana al 100%
      expect(perfectScore, greaterThan(0.95));

      // Postura divergente (manos invertidas)
      final divergentLandmarks = List.generate(
        21,
        (i) => LandmarkPoint(x: 0.5 - i * 0.05, y: 0.5 - i * 0.05),
      );
      final divergentPose = BodyPose(
        hands: [HandPose(landmarks: divergentLandmarks)],
      );

      final lowScore = evaluator.execute(
        userPose: divergentPose,
        referenceFrame: refFrame,
        animationProgress: 0.0,
      );

      expect(lowScore, lessThan(perfectScore));
    });
  });

  group('Dataset and Factory Overrides Separation Tests', () {
    test('SignRepository tracks factory count and clears overrides cleanly', () async {
      final storage = LocalStorageDataSource();
      final repo = SignRepositoryImpl(storage);

      await repo.initialize();

      // Guardar una seña modificada por el usuario
      final customSample = [
        List.generate(63, (i) => 0.5),
      ];
      await repo.saveSign('TEST_SIGN', customSample);

      expect(repo.hasCustomOverrides, isTrue);
      expect(repo.customOverridesCount, 1);
      expect(repo.signDatabase.containsKey('TEST_SIGN'), isTrue);

      // Restablecer a valores de fábrica
      await repo.clearCustomSigns();

      expect(repo.hasCustomOverrides, isFalse);
      expect(repo.customOverridesCount, 0);
      expect(repo.signDatabase.containsKey('TEST_SIGN'), isFalse);
    });
  });
}
