import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/services/tts_service.dart';
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
import '../../domain/usecases/recognize_word_sign_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

class TranslationViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final IVisionRepository visionRepository;
  final ISignRepository signRepository;
  final ISettingsRepository? settingsRepository;
  final ITtsService? ttsService;
  final PredictSignUseCase predictSignUseCase;
  final CalibrateSignUseCase calibrateSignUseCase;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;
  final RecognizeWordSignUseCase recognizeWordSignUseCase;

  StreamSubscription? _handSubscription;
  StreamSubscription? _faceSubscription;

  List<HandPose> _rawHands = [];
  List<FaceBounds> _rawFaces = [];
  Size? _viewportSize;

  bool _isInitialized = false;
  String _statusMessage = 'Iniciando sistema LSC...';
  SignPrediction? _currentPrediction;
  BodyPose? _currentPose;

  // Historial de las últimas 5 palabras reconocidas
  final List<String> _recentWords = [];
  DateTime _lastWordTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Calibración (Placeholder no funcional en UI)
  bool _isCalibrating = false;
  String _targetLetter = 'A';
  final List<List<double>> _calibrationBuffer = [];
  final int totalCalibrationSamples = 30;

  TranslationViewModel({
    required this.cameraDataSource,
    required this.visionRepository,
    required this.signRepository,
    this.settingsRepository,
    this.ttsService,
    required this.predictSignUseCase,
    required this.calibrateSignUseCase,
    required this.resolveBodyPoseUseCase,
    RecognizeWordSignUseCase? recognizeWordSignUseCase,
  }) : recognizeWordSignUseCase =
            recognizeWordSignUseCase ?? RecognizeWordSignUseCase();

  bool get isInitialized => _isInitialized;
  String get statusMessage => _statusMessage;
  SignPrediction? get currentPrediction => _currentPrediction;
  BodyPose? get currentPose => _currentPose;
  bool get hasHand => _currentPose?.hasHand ?? false;
  List<String> get recentWords => List.unmodifiable(_recentWords);

  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;
  bool get isCameraSwitching => cameraDataSource.isSwitching;
  bool get isCameraPermissionDenied => cameraDataSource.isPermissionDenied;
  String? get cameraErrorMessage => cameraDataSource.errorMessage;

  bool get isCalibrating => _isCalibrating;
  String get targetLetter => _targetLetter;
  int get calibrationSamplesCount => _calibrationBuffer.length;
  double get calibrationProgress =>
      _calibrationBuffer.length / totalCalibrationSamples;

  int get calibratedSignsCount => signRepository.calibratedCount;

  Future<void> initialize() async {
    _statusMessage = 'Cargando base de datos LSC...';
    notifyListeners();

    await signRepository.initialize();
    await visionRepository.initialize();
    await ttsService?.initialize();
    visionRepository.setRotation(settingsRepository?.modelRotationDegrees ?? 270);

    await _handSubscription?.cancel();
    _handSubscription = visionRepository.handStream.listen(_onHandsDetected);

    await _faceSubscription?.cancel();
    _faceSubscription = visionRepository.faceStream.listen(_onFacesDetected);

    _statusMessage = 'Inicializando cámara...';
    notifyListeners();

    await cameraDataSource.initializeCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );

    if (cameraDataSource.isInitialized) {
      _isInitialized = true;
      _statusMessage = 'LSC RT listo';
    } else {
      _statusMessage = cameraDataSource.errorMessage ?? 'Error al conectar cámara';
    }
    notifyListeners();
  }

  Future<void> retryCamera() async {
    _statusMessage = 'Reintentando conexión con la cámara...';
    notifyListeners();
    await cameraDataSource.initializeCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );
    if (cameraDataSource.isInitialized) {
      _isInitialized = true;
      _statusMessage = 'LSC RT listo';
    } else {
      _statusMessage = cameraDataSource.errorMessage ?? 'Error al conectar cámara';
    }
    notifyListeners();
  }

  void setViewportSize(Size size) {
    if (_viewportSize == size) return;
    _viewportSize = size;
    _recomputeBodyPose();
  }

  Future<void> switchCamera() async {
    if (cameraDataSource.cameras.length < 2 || cameraDataSource.isSwitching) return;
    resolveBodyPoseUseCase.reset();
    recognizeWordSignUseCase.reset();
    _currentPrediction = null;
    _currentPose = null;
    notifyListeners();

    await cameraDataSource.switchCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );
    notifyListeners();
  }

  void _onHandsDetected(List<HandPose> hands) {
    _rawHands = hands;
    _recomputeBodyPose();

    if (hands.isEmpty) {
      _currentPrediction = null;
      recognizeWordSignUseCase.reset();
    } else {
      // 1. Prioridad: Clasificador de señas de palabras (Bimanuales y Unimanuales Core)
      final wordPred = recognizeWordSignUseCase.execute(
        hands: _rawHands,
        pose: _currentPose,
      );

      if (wordPred != null &&
          wordPred.isRecognized &&
          wordPred.confidence >= 0.70) {
        _currentPrediction = wordPred;
        _registerRecognizedWord(wordPred.label);
      } else if (hands.length == 1) {
        // 2. Detección de Letras del Abecedario (Dactilología individual estática)
        final letterPred = predictSignUseCase.execute(hands.first);
        _currentPrediction = letterPred;

        if (letterPred != null &&
            letterPred.isRecognized &&
            letterPred.confidence >= 0.70) {
          _registerRecognizedWord(letterPred.label);
        }
      } else {
        _currentPrediction = wordPred;
      }

      // Si estuviera en modo calibración
      if (_isCalibrating && _calibrationBuffer.length < totalCalibrationSamples) {
        final sample = calibrateSignUseCase.extractNormalizedFeatures(hands.first);
        if (sample.isNotEmpty) {
          _calibrationBuffer.add(sample);
          if (_calibrationBuffer.length >= totalCalibrationSamples) {
            _finishCalibration();
          }
        }
      }
    }

    notifyListeners();
  }

  void _registerRecognizedWord(String word) {
    final now = DateTime.now();
    if (_recentWords.isNotEmpty &&
        _recentWords.last == word &&
        now.difference(_lastWordTime).inMilliseconds < 2500) {
      return;
    }

    _lastWordTime = now;
    _recentWords.add(word);
    if (_recentWords.length > 5) {
      _recentWords.removeAt(0);
    }

    // Audio no bloqueante
    ttsService?.speak(word);
  }

  void clearRecentWords() {
    _recentWords.clear();
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

  // --- Métodos de Calibración ---
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
    ttsService?.dispose();
    super.dispose();
  }
}
