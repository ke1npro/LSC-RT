import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language_app/core/config/offline_video_config.dart';
import 'package:sign_language_app/core/theme/app_theme.dart';
import 'package:sign_language_app/core/utils/dictionary_import_validator.dart';
import 'package:sign_language_app/data/datasources/camera_datasource.dart';
import 'package:sign_language_app/data/datasources/encrypted_file_datasource.dart';
import 'package:sign_language_app/data/datasources/local_storage_datasource.dart';
import 'package:sign_language_app/data/datasources/secure_storage_datasource.dart';
import 'package:sign_language_app/data/datasources/video_landmarker_datasource.dart';
import 'package:sign_language_app/data/repositories/dictionary_repository_impl.dart';
import 'package:sign_language_app/data/repositories/settings_repository_impl.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';
import 'package:sign_language_app/domain/entities/sign_take_candidate.dart';
import 'package:sign_language_app/presentation/screens/dictionary/widgets/video_trimmer_view.dart';
import 'package:sign_language_app/presentation/viewmodels/sign_recorder_viewmodel.dart';
import 'package:sign_language_app/presentation/viewmodels/step_conversation_viewmodel.dart';

RecordedSign _buildAccentedSign({
  required String id,
  required String word,
}) {
  return RecordedSign(
    id: id,
    word: word,
    category: 'Familia',
    requiredHands: 1,
    fps: 20.0,
    detectionRate: 1.0,
    averageConfidence: 0.92,
    totalTakesEvaluated: 1,
    createdAt: DateTime(2026, 11, 26),
    frames: List.generate(
      5,
      (i) => SignFrameLandmarks(
        frameIndex: i,
        timestampMs: i * 50,
        hands: [
          HandPose(
            landmarks: List.generate(
              21,
              (k) => LandmarkPoint(x: 0.4 + k * 0.01, y: 0.5, z: 0.0),
            ),
            confidence: 0.92,
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('Accented sign ID slugification and persistence', () {
    late Directory tmp;
    late SecureStorageDataSource secure;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      secure = SecureStorageDataSource();
      tmp = Directory.systemTemp.createTempSync('lsc_accent_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('buildSignId converts accented characters into ASCII safe IDs', () {
      const ts = 1700000000000;
      expect(
        SignRecorderViewModel.buildSignId('PAPÁ', ts),
        equals('papa_$ts'),
      );
      expect(
        SignRecorderViewModel.buildSignId('NIÑO', ts),
        equals('nino_$ts'),
      );
      expect(
        SignRecorderViewModel.buildSignId('¿CÓMO ESTÁS?', ts),
        equals('como_estas_$ts'),
      );
      expect(
        SignRecorderViewModel.buildSignId('   ', ts),
        equals('sign_$ts'),
      );
    });

    test('generated IDs pass DictionaryImportValidator for Spanish words', () {
      const ts = 1700000000000;
      for (final word in const ['PAPÁ', 'NIÑO', '¿CÓMO ESTÁS?', '   ', 'BUENOS DÍAS']) {
        final id = SignRecorderViewModel.buildSignId(word, ts);
        final json = _buildAccentedSign(id: id, word: 'PAPÁ').toJson();
        expect(
          DictionaryImportValidator.isValidSignJson(json),
          isTrue,
          reason: 'Expected ID "$id" for "$word" to pass DictionaryImportValidator',
        );
      }
    });

    test('saving and reloading PAPÁ and NIÑO preserves words cleanly', () async {
      final repo1 = DictionaryRepositoryImpl(
        EncryptedFileDataSource(secure),
        baseDir: tmp,
      );
      await repo1.initialize();

      final papaId = SignRecorderViewModel.buildSignId('PAPÁ', 1700000000001);
      final ninoId = SignRecorderViewModel.buildSignId('NIÑO', 1700000000002);

      await repo1.saveRecordedSign(_buildAccentedSign(id: papaId, word: 'PAPÁ'));
      await repo1.saveRecordedSign(_buildAccentedSign(id: ninoId, word: 'NIÑO'));

      final repo2 = DictionaryRepositoryImpl(
        EncryptedFileDataSource(secure),
        baseDir: tmp,
      );
      await repo2.initialize();

      expect(repo2.allSigns.length, 2);
      expect(repo2.getSignById(papaId)?.word, equals('PAPÁ'));
      expect(repo2.getSignById(ninoId)?.word, equals('NIÑO'));
    });
  });

  group('OfflineVideoConfig and SettingsRepositoryImpl persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('OfflineVideoConfig maps quality presets and sanitizes invalid values', () {
      expect(OfflineVideoConfig.maxDimensionForPreset('high'), 480);
      expect(OfflineVideoConfig.maxDimensionForPreset('medium'), 360);
      expect(OfflineVideoConfig.maxDimensionForPreset('low'), 256);
      expect(OfflineVideoConfig.maxDimensionForPreset('unknown'), 360);

      expect(OfflineVideoConfig.sanitizeFps(30), 30);
      expect(OfflineVideoConfig.sanitizeFps(20), 20);
      expect(OfflineVideoConfig.sanitizeFps(15), 15);
      expect(OfflineVideoConfig.sanitizeFps(60), OfflineVideoConfig.defaultFps);

      expect(OfflineVideoConfig.sanitizePreset('HIGH'), 'high');
      expect(OfflineVideoConfig.sanitizePreset('invalid'), OfflineVideoConfig.defaultPreset);
    });

    test('SettingsRepositoryImpl persists offlineVideoFps and offlineQualityPreset', () async {
      final repo1 = SettingsRepositoryImpl(LocalStorageDataSource());
      await repo1.initialize();
      expect(repo1.offlineVideoFps, OfflineVideoConfig.defaultFps);
      expect(repo1.offlineQualityPreset, OfflineVideoConfig.defaultPreset);

      await repo1.setOfflineVideoFps(15);
      await repo1.setOfflineQualityPreset('low');

      final repo2 = SettingsRepositoryImpl(LocalStorageDataSource());
      await repo2.initialize();
      expect(repo2.offlineVideoFps, 15);
      expect(repo2.offlineQualityPreset, 'low');
    });

    test('StepConversationViewModel selectQualityPreset persists selection', () async {
      final settings = SettingsRepositoryImpl(LocalStorageDataSource());
      await settings.initialize();
      final dict = DictionaryRepositoryImpl(
        EncryptedFileDataSource(SecureStorageDataSource()),
      );
      final vm = StepConversationViewModel(
        cameraDataSource: CameraDataSource(const []),
        videoDataSource: VideoLandmarkerDataSource(),
        dictionaryRepository: dict,
        settingsRepository: settings,
      );

      expect(vm.activeQualityPreset, 'medium');
      await vm.selectQualityPreset('low');
      expect(vm.activeQualityPreset, 'low');
      expect(settings.offlineQualityPreset, 'low');
      vm.dispose();
    });
  });

  group('VideoTrimmerView WhatsApp timeline widget tests', () {
    testWidgets('renders WhatsApp timeline handles and fires onTrimChanged on start handle drag',
        (WidgetTester tester) async {
      final frames = List.generate(
        40,
        (i) => SignFrameLandmarks(
          frameIndex: i,
          timestampMs: i * 50,
          hands: i >= 5 && i <= 34
              ? [
                  HandPose(
                    landmarks: List.generate(
                      21,
                      (k) => LandmarkPoint(x: 0.4 + k * 0.01, y: 0.5, z: 0.0),
                    ),
                    confidence: 0.9,
                  ),
                ]
              : const [],
        ),
      );
      final candidate = SignTakeCandidate(
        takeNumber: 1,
        tempVideoPath: '/nonexistent/sample.mp4',
        allFrames: frames,
        videoDurationMs: 2000,
        trimStartFrame: 0,
        trimEndFrame: 39,
      );

      int? reportedStart;
      int? reportedEnd;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: VideoTrimmerView(
              candidate: candidate,
              requiredHands: 1,
              onTrimChanged: (s, e) {
                reportedStart = s;
                reportedEnd = e;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Inicio:'), findsOneWidget);
      expect(find.textContaining('Fin:'), findsOneWidget);
      expect(find.textContaining('Reconocimiento:'), findsOneWidget);

      // Drag near left handle rightward to advance trimStartFrame
      final gestureDetector = find.byType(GestureDetector).last;
      final rect = tester.getRect(gestureDetector);
      final startPoint = Offset(rect.left + 8, rect.center.dy);
      await tester.dragFrom(startPoint, const Offset(60, 0));
      await tester.pump();

      expect(reportedStart, isNotNull);
      expect(reportedStart!, greaterThan(0));
      expect(reportedEnd, equals(39));
    });
  });
}
