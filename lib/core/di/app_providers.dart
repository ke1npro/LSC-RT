import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../data/datasources/camera_datasource.dart';
import '../../data/datasources/local_storage_datasource.dart';
import '../../data/datasources/vision_datasource_factory.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/sign_repository_impl.dart';
import '../../data/repositories/vision_repository_impl.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_sign_repository.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../../domain/usecases/calibrate_sign_usecase.dart';
import '../../domain/usecases/evaluate_posture_usecase.dart';
import '../../domain/usecases/generate_wave_guide_usecase.dart';
import '../../domain/usecases/predict_sign_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../presentation/viewmodels/settings_viewmodel.dart';
import '../../presentation/viewmodels/teaching_viewmodel.dart';
import '../../presentation/viewmodels/translation_viewmodel.dart';

class AppProviders {
  AppProviders._();

  static List<SingleChildWidget> buildProviders(List<CameraDescription> cameras) {
    final localStorage = LocalStorageDataSource();
    final visionDataSource = getVisionDataSource();
    final cameraDataSource = CameraDataSource(cameras);

    final IVisionRepository visionRepo = VisionRepositoryImpl(visionDataSource);
    final ISignRepository signRepo = SignRepositoryImpl(localStorage);
    final ISettingsRepository settingsRepo = SettingsRepositoryImpl(localStorage);

    final predictUseCase = PredictSignUseCase(signRepo);
    final calibrateUseCase = CalibrateSignUseCase(signRepo, predictUseCase);
    final waveUseCase = GenerateWaveGuideUseCase();
    final evaluateUseCase = EvaluatePostureUseCase();

    return [
      Provider<CameraDataSource>.value(value: cameraDataSource),
      Provider<IVisionRepository>.value(value: visionRepo),
      Provider<ISignRepository>.value(value: signRepo),
      Provider<ISettingsRepository>.value(value: settingsRepo),
      ChangeNotifierProvider<SettingsViewModel>(
        create: (_) => SettingsViewModel(settingsRepo)..initialize(),
      ),
      ChangeNotifierProvider<TranslationViewModel>(
        create: (_) => TranslationViewModel(
          cameraDataSource: cameraDataSource,
          visionRepository: visionRepo,
          signRepository: signRepo,
          settingsRepository: settingsRepo,
          predictSignUseCase: predictUseCase,
          calibrateSignUseCase: calibrateUseCase,
          resolveBodyPoseUseCase: ResolveBodyPoseUseCase(),
        ),
      ),
      ChangeNotifierProvider<TeachingViewModel>(
        create: (_) => TeachingViewModel(
          cameraDataSource: cameraDataSource,
          visionRepository: visionRepo,
          settingsRepository: settingsRepo,
          resolveBodyPoseUseCase: ResolveBodyPoseUseCase(),
          generateWaveGuideUseCase: waveUseCase,
          evaluatePostureUseCase: evaluateUseCase,
        ),
      ),
    ];
  }
}
