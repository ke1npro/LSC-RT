import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../domain/entities/body_pose.dart';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/entities/sign_prediction.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_sign_repository.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../../domain/usecases/calibrate_sign_usecase.dart';
import '../../domain/usecases/predict_sign_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

class TranslationViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final IVisionRepository visionRepository;
  final ISignRepository signRepository;
  final ISettingsRepository? settingsRepository;
  final PredictSignUseCase predictSignUseCase;
  final CalibrateSignUseCase calibrateSignUseCase;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;

  StreamSubscription? _handSubscription;
  StreamSubscription? _faceSubscription;

  List<HandPose> _rawHands = [];
  List<FaceBounds> _rawFaces = [];
  Size? _viewportSize;

  bool _isInitialized = false;
  String _statusMessage = 'Iniciando sistema LSC...';
  SignPrediction? _currentPrediction;
  BodyPose? _currentPose;

  // Calibración
  bool _isCalibrating = false;
  String _targetLetter = 'A';
  final List<List<double>> _calibrationBuffer = [];
  final int totalCalibrationSamples = 30;

  TranslationViewModel({
    required this.cameraDataSource,
    required this.visionRepository,
    required this.signRepository,
    this.settingsRepository,
    required this.predictSignUseCase,
    required this.calibrateSignUseCase,
    required this.resolveBodyPoseUseCase,
  });

  bool get isInitialized => _isInitialized;
  String get statusMessage => _statusMessage;
  SignPrediction? get currentPrediction => _currentPrediction;
  BodyPose? get currentPose => _currentPose;
  bool get hasHand => _currentPose?.hasHand ?? false;
  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;

  bool get isCalibrating => _isCalibrating;
  String get targetLetter => _targetLetter;
  int get calibrationSamplesCount => _calibrationBuffer.length;
  int get calibratedSignsCount => signRepository.calibratedCount;

  Future<void> initialize() async {
    _statusMessage = 'Cargando base de datos LSC...';
    notifyListeners();

    await signRepository.initialize();
    await visionRepository.initialize();
    visionRepository.setRotation(settingsRepository?.modelRotationDegrees ?? 90);

    await _handSubscription?.cancel();
    _handSubscription = visionRepository.handStream.listen(_onHandsDetected);

    await _faceSubscription?.cancel();
    _faceSubscription = visionRepository.faceStream.listen(_onFacesDetected);

    if (cameraDataSource.cameras.isNotEmpty) {
      _statusMessage = 'Inicializando cámara...';
      notifyListeners();
      try {
        await cameraDataSource.initializeCamera(
          onFrame: (image, orientation) {
            visionRepository.processFrame(image, orientation);
          },
        );
        _isInitialized = true;
        _statusMessage = 'LSC RT listo';
      } catch (e) {
        _statusMessage = 'Error al abrir cámara: $e';
      }
    } else {
      _statusMessage = 'No se encontraron cámaras';
    }
    notifyListeners();
  }

  void setViewportSize(Size size) {
    if (_viewportSize == size) return;
    _viewportSize = size;
    _recomputeBodyPose();
  }

  Future<void> switchCamera() async {
    if (cameraDataSource.cameras.length < 2) return;
    resolveBodyPoseUseCase.reset();
    await cameraDataSource.switchCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );
    notifyListeners();
  }

  void _onHandsDetected(List<HandPose> hands) {
    _rawHands = hands;
    if (hands.isEmpty) {
      _currentPrediction = null;
    } else {
      final hand = hands.first;
      // Predecir signo
      _currentPrediction = predictSignUseCase.execute(hand);

      // Si está en modo calibración, acumular muestra
      if (_isCalibrating && _calibrationBuffer.length < totalCalibrationSamples) {
        final sample = calibrateSignUseCase.extractNormalizedFeatures(hand);
        if (sample.isNotEmpty) {
          _calibrationBuffer.add(sample);
          if (_calibrationBuffer.length >= totalCalibrationSamples) {
            _finishCalibration();
          }
        }
      }
    }

    _recomputeBodyPose();
    notifyListeners();
  }

  void _onFacesDetected(List<FaceBounds> faces) {
    _rawFaces = faces;
    _recomputeBodyPose();
    notifyListeners();
  }

  void _recomputeBodyPose() {
    final size = _viewportSize ?? const Size(400, 600);
    _currentPose = resolveBodyPoseUseCase.execute(
      hands: _rawHands,
      faces: _rawFaces,
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  void startCalibration(String letter) {
    _targetLetter = letter;
    _calibrationBuffer.clear();
    _isCalibrating = true;
    notifyListeners();
  }

  void cancelCalibration() {
    _isCalibrating = false;
    _calibrationBuffer.clear();
    notifyListeners();
  }

  Future<void> _finishCalibration() async {
    if (_calibrationBuffer.isNotEmpty) {
      await calibrateSignUseCase.saveCalibration(
        _targetLetter,
        List.from(_calibrationBuffer),
      );
    }
    _isCalibrating = false;
    _calibrationBuffer.clear();
    notifyListeners();
  }

  Future<void> clearAllCustomCalibrations() async {
    await calibrateSignUseCase.clearAllCalibrations();
    notifyListeners();
  }

  @override
  void dispose() {
    _handSubscription?.cancel();
    _faceSubscription?.cancel();
    resolveBodyPoseUseCase.reset();
    super.dispose();
  }
}
