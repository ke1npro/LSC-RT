import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../services/tts_service.dart';
import '../../data/datasources/avatar_motion_datasource.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../data/datasources/local_storage_datasource.dart';
import '../../data/datasources/secure_storage_datasource.dart';
import '../../data/datasources/video_landmarker_datasource.dart';
import '../../data/datasources/vision_datasource_factory.dart';
import '../../data/repositories/dictionary_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/sign_repository_impl.dart';
import '../../data/repositories/vision_repository_impl.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_sign_repository.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../../domain/usecases/calibrate_sign_usecase.dart';
import '../../domain/usecases/evaluate_posture_usecase.dart';
import '../../domain/usecases/generate_wave_guide_usecase.dart';
import '../../domain/usecases/predict_sign_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../domain/usecases/select_best_take_usecase.dart';
import '../../presentation/viewmodels/avatar_viewmodel.dart';
import '../../presentation/viewmodels/dictionary_viewmodel.dart';
import '../../presentation/viewmodels/settings_viewmodel.dart';
import '../../presentation/viewmodels/sign_recorder_viewmodel.dart';
import '../../presentation/viewmodels/teaching_viewmodel.dart';
import '../../presentation/viewmodels/translation_viewmodel.dart';

class AppProviders {
  AppProviders._();

  static List<SingleChildWidget> buildProviders(List<CameraDescription> cameras) {
    final localStorage = LocalStorageDataSource();
    final secureStorage = SecureStorageDataSource(legacyStorage: localStorage);
    final visionDataSource = getVisionDataSource();
    final cameraDataSource = CameraDataSource(cameras);
    final videoDataSource = VideoLandmarkerDataSource();
    final avatarDataSource = AvatarMotionDataSource();
    final ttsService = TtsService();

    final IVisionRepository visionRepo = VisionRepositoryImpl(visionDataSource);
    final ISignRepository signRepo = SignRepositoryImpl(localStorage, secureStorage);
    final ISettingsRepository settingsRepo = SettingsRepositoryImpl(localStorage);
    final IDictionaryRepository dictionaryRepo = DictionaryRepositoryImpl(secureStorage);

    final predictUseCase = PredictSignUseCase(signRepo);
    final calibrateUseCase = CalibrateSignUseCase(signRepo, predictUseCase);
    final waveUseCase = GenerateWaveGuideUseCase();
    final evaluateUseCase = EvaluatePostureUseCase();
    final selectBestTakeUseCase = SelectBestTakeUseCase();

    return [
      Provider<CameraDataSource>.value(value: cameraDataSource),
      Provider<VideoLandmarkerDataSource>.value(value: videoDataSource),
      Provider<IVisionRepository>.value(value: visionRepo),
      Provider<ISignRepository>.value(value: signRepo),
      Provider<ISettingsRepository>.value(value: settingsRepo),
      Provider<IDictionaryRepository>.value(value: dictionaryRepo),
      Provider<AvatarMotionDataSource>.value(value: avatarDataSource),
      Provider<ITtsService>.value(value: ttsService),
      ChangeNotifierProvider<DictionaryViewModel>(
        create: (_) => DictionaryViewModel(dictionaryRepo)..initialize(),
      ),
      ChangeNotifierProvider<SignRecorderViewModel>(
        create: (_) => SignRecorderViewModel(
          cameraDataSource: cameraDataSource,
          videoDataSource: videoDataSource,
          dictionaryRepository: dictionaryRepo,
          selectBestTakeUseCase: selectBestTakeUseCase,
        ),
      ),
      ChangeNotifierProvider<SettingsViewModel>(
        create: (_) => SettingsViewModel(settingsRepo, signRepo, visionRepo)..initialize(),
      ),
      ChangeNotifierProvider<TranslationViewModel>(
        create: (_) => TranslationViewModel(
          cameraDataSource: cameraDataSource,
          visionRepository: visionRepo,
          signRepository: signRepo,
          settingsRepository: settingsRepo,
          ttsService: ttsService,
          predictSignUseCase: predictUseCase,
          calibrateSignUseCase: calibrateUseCase,
          resolveBodyPoseUseCase: ResolveBodyPoseUseCase(),
        ),
      ),
      ChangeNotifierProvider<AvatarViewModel>(
        create: (_) => AvatarViewModel(avatarDataSource)..initialize(),
      ),
      ChangeNotifierProvider<TeachingViewModel>(
        create: (_) => TeachingViewModel(
          cameraDataSource: cameraDataSource,
          visionRepository: visionRepo,
          settingsRepository: settingsRepo,
          resolveBodyPoseUseCase: ResolveBodyPoseUseCase(),
          generateWaveGuideUseCase: waveUseCase,
          evaluatePostureUseCase: evaluateUseCase,
          avatarMotionDataSource: avatarDataSource,
        ),
      ),
    ];
  }
}
