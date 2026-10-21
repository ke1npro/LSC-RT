import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language_app/core/di/app_providers.dart';
import 'package:sign_language_app/core/theme/app_theme.dart';
import 'package:sign_language_app/data/datasources/local_storage_datasource.dart';
import 'package:sign_language_app/data/repositories/sign_repository_impl.dart';
import 'package:sign_language_app/domain/entities/face_bounds.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/sign_prediction.dart';
import 'package:sign_language_app/domain/usecases/evaluate_posture_usecase.dart';
import 'package:sign_language_app/domain/usecases/generate_wave_guide_usecase.dart';
import 'package:sign_language_app/domain/usecases/predict_sign_usecase.dart';
import 'package:sign_language_app/domain/usecases/resolve_body_pose_usecase.dart';
import 'package:sign_language_app/main.dart';
import 'package:sign_language_app/presentation/screens/settings/settings_screen.dart';
import 'package:sign_language_app/presentation/widgets/camera_viewport.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Domain Entities & Models', () {
    test('SignPrediction entity test', () {
      const pred = SignPrediction(label: 'A', confidence: 0.95);
      expect(pred.label, 'A');
      expect(pred.confidence, 0.95);
      expect(pred.isRecognized, isTrue);
      expect(pred.toString(), contains('A (95.0%)'));
    });

    test('HandPose validation test', () {
      final invalidHand = HandPose(landmarks: []);
      expect(invalidHand.isValid, isFalse);

      final validLandmarks = List.generate(
        21,
        (i) => LandmarkPoint(x: i * 0.04, y: i * 0.04),
      );
      final validHand = HandPose(landmarks: validLandmarks);
      expect(validHand.isValid, isTrue);
      expect(validHand.wrist.x, 0.0);
      expect(validHand.middleTip.x, closeTo(0.48, 0.01));
    });
  });

  group('Domain Use Cases', () {
    test('ResolveBodyPoseUseCase calculates Two-Bone IK and arm skeleton', () {
      final useCase = ResolveBodyPoseUseCase();
      final landmarks = List.generate(
        21,
        (i) => LandmarkPoint(x: 0.65, y: 0.50 + i * 0.01),
      );
      final hand = HandPose(landmarks: landmarks);
      final face = FaceBounds(left: 0.4, top: 0.1, width: 0.2, height: 0.3);

      final bodyPose = useCase.execute(
        hands: [hand],
        faces: [face],
        logicalWidth: 400,
        logicalHeight: 800,
      );

      expect(bodyPose.hasHand, isTrue);
      expect(bodyPose.arms.length, 1);
      final arm = bodyPose.arms.first;
      expect(arm.isRightArm, isTrue);
      expect(arm.shoulder, isNotNull);
      expect(arm.elbow, isNotNull);
      expect(arm.sternum, isNotNull);
    });

    test('GenerateWaveGuideUseCase generates valid wave arm and 21 landmarks', () {
      final useCase = GenerateWaveGuideUseCase();
      final guide = useCase.execute(animationProgress: 0.25, viewportWidth: 400);

      expect(guide.arms.length, 1);
      expect(guide.hands.length, 1);
      expect(guide.hands.first.landmarks.length, 21);
    });

    test('EvaluatePostureUseCase evaluates matching score between 0.0 and 1.0', () {
      final waveGen = GenerateWaveGuideUseCase();
      final evaluator = EvaluatePostureUseCase();

      final guide = waveGen.execute(animationProgress: 0.0, viewportWidth: 400);
      final score = evaluator.execute(
        userPose: guide,
        guidePose: guide,
        animationProgress: 0.0,
      );

      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(1.0));
    });

    test('PredictSignUseCase returns null or unrecognized for empty database', () {
      final signRepo = SignRepositoryImpl(LocalStorageDataSource());
      final predictor = PredictSignUseCase(signRepo);
      final landmarks = List.generate(
        21,
        (i) => LandmarkPoint(x: i * 0.02, y: i * 0.02),
      );
      final pred = predictor.execute(HandPose(landmarks: landmarks));

      expect(pred?.isRecognized ?? false, isFalse);
    });
  });

  group('Presentation & Widgets', () {
    testWidgets('LscApp mounts MultiProvider and MainScaffold without crash', (WidgetTester tester) async {
      await tester.pumpWidget(const LscApp());
      expect(find.byType(LscApp), findsOneWidget);
    });

    testWidgets('SettingsScreen displays cleanly with structured cards', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.buildProviders([]),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('SUPERPOSICIONES Y VISIÓN'), findsOneWidget);
      expect(find.text('Overlay MediaPipe en Traducción'), findsOneWidget);
      expect(find.text('Detección y Visor Facial'), findsOneWidget);
      expect(find.text('Overlay MediaPipe en Enseñanza'), findsOneWidget);
      expect(find.text('Orientación del Modelo (MediaPipe)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('PRÓXIMAS FUNCIONALIDADES (HOJA DE RUTA)'),
        200,
      );
      await tester.pumpAndSettle();

      expect(find.text('PRÓXIMAS FUNCIONALIDADES (HOJA DE RUTA)'), findsOneWidget);
      expect(find.text('Texto a Voz en Tiempo Real (TTS)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CameraViewport gracefully displays permission denied without crash', (WidgetTester tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: CameraViewport(
              controller: null,
              isPermissionDenied: true,
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Permiso de Cámara Denegado'), findsOneWidget);
      expect(find.text('Reintentar Conexión'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Reintentar Conexión'));
      expect(retried, isTrue);
    });

    testWidgets('CameraViewport displays switching transition state cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: CameraViewport(
              controller: null,
              isSwitching: true,
            ),
          ),
        ),
      );

      expect(find.text('Cambiando de cámara...'), findsOneWidget);
      expect(find.text('Alineando nuevo sensor de video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
