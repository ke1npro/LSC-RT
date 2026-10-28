import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/sign_prediction.dart';
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

    test('RecognizeWordSignUseCase recognizes unimanual GRACIAS statically near chin', () {
      final useCase = RecognizeWordSignUseCase();
      // Mano abierta frente a la barbilla: muñeca en y=0.50, dedos extendidos hacia arriba en y=0.38..0.44
      final landmarks = List.generate(21, (i) {
        if (i == 0) return const LandmarkPoint(x: 0.50, y: 0.50); // Muñeca
        if (i == 4) return const LandmarkPoint(x: 0.44, y: 0.42); // Pulgar
        if (i == 2) return const LandmarkPoint(x: 0.46, y: 0.46);
        if (i == 8) return const LandmarkPoint(x: 0.49, y: 0.40); // Índice tip
        if (i == 6) return const LandmarkPoint(x: 0.49, y: 0.45); // Índice PIP
        if (i == 12) return const LandmarkPoint(x: 0.51, y: 0.38); // Medio tip
        if (i == 10) return const LandmarkPoint(x: 0.51, y: 0.44); // Medio PIP
        if (i == 16) return const LandmarkPoint(x: 0.53, y: 0.40); // Anular tip
        if (i == 14) return const LandmarkPoint(x: 0.53, y: 0.45); // Anular PIP
        if (i == 20) return const LandmarkPoint(x: 0.55, y: 0.42); // Meñique tip
        if (i == 18) return const LandmarkPoint(x: 0.55, y: 0.46); // Meñique PIP
        return const LandmarkPoint(x: 0.50, y: 0.48);
      });

      final result = useCase.execute(
        hands: [HandPose(landmarks: landmarks)],
        pose: null,
      );

      expect(result, isNotNull);
      expect(result!.label, equals('GRACIAS'));
      expect(result.confidence, greaterThanOrEqualTo(0.92));
    });

    test('RecognizeWordSignUseCase recognizes dynamic GRACIAS trajectory from chin to chest', () {
      final useCase = RecognizeWordSignUseCase();
      // Simular 4 frames de descenso de la mano abierta
      SignPrediction? lastResult;
      for (int f = 0; f < 4; f++) {
        final currentY = 0.48 + (f * 0.02); // 0.48 -> 0.54
        final landmarks = List.generate(21, (i) {
          if (i == 0) return LandmarkPoint(x: 0.50, y: currentY);
          if (i == 4) return LandmarkPoint(x: 0.44, y: currentY - 0.08);
          if (i == 2) return LandmarkPoint(x: 0.46, y: currentY - 0.04);
          if (i == 8) return LandmarkPoint(x: 0.49, y: currentY - 0.10);
          if (i == 6) return LandmarkPoint(x: 0.49, y: currentY - 0.05);
          if (i == 12) return LandmarkPoint(x: 0.51, y: currentY - 0.12);
          if (i == 10) return LandmarkPoint(x: 0.51, y: currentY - 0.06);
          if (i == 16) return LandmarkPoint(x: 0.53, y: currentY - 0.10);
          if (i == 14) return LandmarkPoint(x: 0.53, y: currentY - 0.05);
          if (i == 20) return LandmarkPoint(x: 0.55, y: currentY - 0.08);
          if (i == 18) return LandmarkPoint(x: 0.55, y: currentY - 0.04);
          return LandmarkPoint(x: 0.50, y: currentY - 0.02);
        });

        lastResult = useCase.execute(
          hands: [HandPose(landmarks: landmarks)],
          pose: null,
        );
      }

      expect(lastResult, isNotNull);
      expect(lastResult!.label, equals('GRACIAS'));
      expect(lastResult.confidence, greaterThanOrEqualTo(0.92));
    });
  });
}
