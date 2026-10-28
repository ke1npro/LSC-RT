import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/usecases/recognize_word_sign_usecase.dart';
import 'package:sign_language_app/domain/usecases/resolve_body_pose_usecase.dart';

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

  group('Word Signs & Core Gestures Recognition Tests', () {
    test('RecognizeWordSignUseCase recognizes bimanual FAMILIA when both hands pinch together', () {
      final useCase = RecognizeWordSignUseCase();

      // Mano izquierda con pellizco (pulgar e índice juntos en Landmark 4 y 8)
      final lLandmarks = List.generate(21, (i) {
        if (i == 4 || i == 8) return const LandmarkPoint(x: 0.45, y: 0.50);
        return LandmarkPoint(x: 0.45, y: 0.50 + (i * 0.005));
      });
      // Mano derecha con pellizco
      final rLandmarks = List.generate(21, (i) {
        if (i == 4 || i == 8) return const LandmarkPoint(x: 0.50, y: 0.50);
        return LandmarkPoint(x: 0.50, y: 0.50 + (i * 0.005));
      });

      final result = useCase.execute(
        hands: [
          HandPose(landmarks: lLandmarks),
          HandPose(landmarks: rLandmarks),
        ],
        pose: null,
      );

      expect(result, isNotNull);
      expect(result!.label, equals('FAMILIA'));
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('RecognizeWordSignUseCase recognizes unimanual BIEN on thumbs-up fist', () {
      final useCase = RecognizeWordSignUseCase();
      // Puño: muñeca en (0.50, 0.60), PIPs en y=0.45, puntas dobladas hacia la muñeca en y=0.52
      final landmarks = List.generate(21, (i) {
        if (i == 0) return const LandmarkPoint(x: 0.50, y: 0.60); // Muñeca
        if (i == 4) return const LandmarkPoint(x: 0.50, y: 0.25); // Pulgar punta (bien arriba)
        if (i == 2) return const LandmarkPoint(x: 0.50, y: 0.40); // Pulgar MCP
        if (i == 6 || i == 10 || i == 14 || i == 18) {
          return const LandmarkPoint(x: 0.50, y: 0.44); // PIP
        }
        return const LandmarkPoint(x: 0.50, y: 0.52); // Tips doblados
      });

      final result = useCase.execute(
        hands: [HandPose(landmarks: landmarks)],
        pose: null,
      );

      expect(result, isNotNull);
      expect(result!.label, equals('BIEN'));
      expect(result.confidence, greaterThanOrEqualTo(0.95));
    });

    test('RecognizeWordSignUseCase recognizes unimanual MAL on thumbs-down fist', () {
      final useCase = RecognizeWordSignUseCase();
      // Puño con pulgar apuntando hacia abajo
      final landmarks = List.generate(21, (i) {
        if (i == 0) return const LandmarkPoint(x: 0.50, y: 0.40); // Muñeca
        if (i == 4) return const LandmarkPoint(x: 0.50, y: 0.70); // Pulgar punta (bien abajo)
        if (i == 2) return const LandmarkPoint(x: 0.50, y: 0.50); // Pulgar MCP
        if (i == 6 || i == 10 || i == 14 || i == 18) {
          return const LandmarkPoint(x: 0.50, y: 0.35); // PIP
        }
        return const LandmarkPoint(x: 0.50, y: 0.38); // Tips doblados
      });

      final result = useCase.execute(
        hands: [HandPose(landmarks: landmarks)],
        pose: null,
      );

      expect(result, isNotNull);
      expect(result!.label, equals('MAL'));
      expect(result.confidence, greaterThanOrEqualTo(0.95));
    });

    test('RecognizeWordSignUseCase recognizes unimanual YO when index points at chest', () {
      final useCase = RecognizeWordSignUseCase();
      // Índice extendido apuntando al centro del pecho
      final landmarks = List.generate(21, (i) {
        if (i == 0) return const LandmarkPoint(x: 0.50, y: 0.38); // muñeca
        if (i == 8) return const LandmarkPoint(x: 0.50, y: 0.52); // indexTip en pecho
        if (i == 6) return const LandmarkPoint(x: 0.50, y: 0.45); // indexPip
        if (i == 10 || i == 14 || i == 18) {
          return const LandmarkPoint(x: 0.50, y: 0.40); // PIPs doblados
        }
        return const LandmarkPoint(x: 0.50, y: 0.39); // otros dedos plegados
      });

      final result = useCase.execute(
        hands: [HandPose(landmarks: landmarks)],
        pose: null,
      );

      expect(result, isNotNull);
      expect(result!.label, equals('YO'));
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });
  });
}
