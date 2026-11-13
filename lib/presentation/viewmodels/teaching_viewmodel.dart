import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/utils/app_logger.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../data/datasources/video_landmarker_datasource.dart';
import '../../domain/entities/body_pose.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/usecases/evaluate_recorded_sign_practice_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

enum TeachingMode {
  catalog,
  demonstration,
  practiceReady,
  practiceCountdown,
  practiceRecording,
  practiceProcessing,
  practiceResult,
}

class TeachingViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final VideoLandmarkerDataSource videoDataSource;
  final IDictionaryRepository dictionaryRepository;
  final ISettingsRepository? settingsRepository;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;
  final EvaluateRecordedSignPracticeUseCase evaluatePracticeUseCase;

  TeachingViewModel({
    required this.cameraDataSource,
    required this.videoDataSource,
    required this.dictionaryRepository,
    this.settingsRepository,
    required this.resolveBodyPoseUseCase,
    EvaluateRecordedSignPracticeUseCase? evaluatePracticeUseCase,
  }) : evaluatePracticeUseCase =
            evaluatePracticeUseCase ?? EvaluateRecordedSignPracticeUseCase();

  bool _isInitialized = false;
  TeachingMode _mode = TeachingMode.catalog;
  RecordedSign? _selectedSign;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';

  // Animación de demostración del esqueleto guía
  int _demoFrameIndex = 0;
  Timer? _demoTimer;
  double _demoSpeed = 1.0;

  // Grabación offline de práctica (máx 6s)
  static const double maxPracticeSeconds = 6.0;
  int _countdownSeconds = 3;
  Timer? _countdownTimer;
  double _recordingSeconds = 0.0;
  Timer? _recordingTimer;

  // Progreso de procesamiento offline
  double _processingPercent = 0.0;
  int _processedFrames = 0;
  int _totalProcessingFrames = 0;
  StreamSubscription<VideoProgressUpdate>? _progressSubscription;

  // Resultado de la evaluación y revisión temporal
  String? _attemptTempVideoPath;
  List<SignFrameLandmarks> _attemptFrames = const [];
  PracticeEvaluationResult? _evaluationResult;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  TeachingMode get mode => _mode;
  RecordedSign? get selectedSign => _selectedSign;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  int get demoFrameIndex => _demoFrameIndex;
  double get demoSpeed => _demoSpeed;

  int get countdownSeconds => _countdownSeconds;
  double get recordingSeconds => _recordingSeconds;
  double get processingPercent => _processingPercent;
  int get processedFrames => _processedFrames;
  int get totalProcessingFrames => _totalProcessingFrames;

  String? get attemptTempVideoPath => _attemptTempVideoPath;
  List<SignFrameLandmarks> get attemptFrames => _attemptFrames;
  PracticeEvaluationResult? get evaluationResult => _evaluationResult;
  String? get errorMessage => _errorMessage;

  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;
  bool get isCameraSwitching => cameraDataSource.isSwitching;
  bool get isCameraPermissionDenied => cameraDataSource.isPermissionDenied;
  String? get cameraErrorMessage => cameraDataSource.errorMessage;

  List<String> get categories {
    final cats = <String>{'Todos'};
    for (final s in dictionaryRepository.allSigns) {
      if (s.category.trim().isNotEmpty) {
        cats.add(s.category.trim());
      }
    }
    return cats.toList();
  }

  List<RecordedSign> get filteredSigns {
    var signs = dictionaryRepository.allSigns;
    if (_selectedCategory != 'Todos') {
      signs = signs
          .where((s) => s.category.toLowerCase() == _selectedCategory.toLowerCase())
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      signs = signs.where((s) {
        return s.word.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q);
      }).toList();
    }
    return signs;
  }

  BodyPose? buildDemoPose(Size size) {
    final sign = _selectedSign;
    if (sign == null || sign.frames.isEmpty) return null;
    final idx = _demoFrameIndex.clamp(0, sign.frames.length - 1);
    final frame = sign.frames[idx];
    return resolveBodyPoseUseCase.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  Future<void> initialize() async {
    if (!dictionaryRepository.isLoaded) {
      await dictionaryRepository.initialize();
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    await dictionaryRepository.initialize();
    notifyListeners();
  }

  void setSelectedCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void selectSign(RecordedSign sign) {
    _selectedSign = sign;
    _mode = TeachingMode.demonstration;
    _demoFrameIndex = 0;
    _errorMessage = null;
    resolveBodyPoseUseCase.reset();
    _startDemoLoop();
    notifyListeners();
  }

  void cycleDemoSpeed() {
    if (_demoSpeed == 1.0) {
      _demoSpeed = 0.5;
    } else if (_demoSpeed == 0.5) {
      _demoSpeed = 1.5;
    } else {
      _demoSpeed = 1.0;
    }
    if (_mode == TeachingMode.demonstration) {
      _startDemoLoop();
    }
    notifyListeners();
  }

  Future<void> backToCatalog() async {
    _stopDemoLoop();
    await _cleanupPracticeSession();
    _selectedSign = null;
    _mode = TeachingMode.catalog;
    notifyListeners();
  }

  Future<void> backToDemonstration() async {
    await _cleanupPracticeSession();
    _mode = TeachingMode.demonstration;
    _demoFrameIndex = 0;
    resolveBodyPoseUseCase.reset();
    _startDemoLoop();
    notifyListeners();
  }

  Future<void> startPracticeSetup() async {
    _stopDemoLoop();
    await _deleteTempVideo();
    _evaluationResult = null;
    _attemptFrames = const [];
    _errorMessage = null;
    _mode = TeachingMode.practiceReady;
    notifyListeners();

    cameraDataSource.setResolutionPreset(ResolutionPreset.high);
    await cameraDataSource.initializeCamera();
    notifyListeners();
  }

  Future<void> retryCamera() async {
    cameraDataSource.setResolutionPreset(ResolutionPreset.high);
    await cameraDataSource.initializeCamera();
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (cameraDataSource.cameras.length < 2 || cameraDataSource.isSwitching) return;
    await cameraDataSource.switchCamera();
    notifyListeners();
  }

  void startPracticeCountdown() {
    _errorMessage = null;
    _mode = TeachingMode.practiceCountdown;
    _countdownSeconds = 3;
    notifyListeners();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _startPracticeRecording();
      }
    });
  }

  Future<void> _startPracticeRecording() async {
    _mode = TeachingMode.practiceRecording;
    _recordingSeconds = 0.0;
    notifyListeners();

    try {
      await cameraDataSource.startVideoRecording();

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        _recordingSeconds += 0.1;
        if (_recordingSeconds >= maxPracticeSeconds) {
          timer.cancel();
          stopPracticeRecording();
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      AppLogger.e('TeachingViewModel: Error iniciando grabación de práctica', e);
      _errorMessage = 'No se pudo iniciar la grabación: $e';
      _mode = TeachingMode.practiceReady;
      notifyListeners();
    }
  }

  Future<void> stopPracticeRecording() async {
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    if (_mode != TeachingMode.practiceRecording) return;

    _mode = TeachingMode.practiceProcessing;
    _processingPercent = 0.0;
    _processedFrames = 0;
    _totalProcessingFrames = 0;
    notifyListeners();

    try {
      final XFile? videoFile = await cameraDataSource.stopVideoRecording();
      if (videoFile == null) {
        throw Exception('La cámara no generó el archivo de video.');
      }

      _attemptTempVideoPath = videoFile.path;
      await cameraDataSource.disposeCamera();
      await _processAndEvaluateAttempt(videoFile.path);
    } catch (e) {
      AppLogger.e('TeachingViewModel: Error deteniendo grabación de práctica', e);
      _errorMessage = 'Error al capturar la práctica: $e';
      _mode = TeachingMode.practiceReady;
      await cameraDataSource.initializeCamera();
      notifyListeners();
    }
  }

  Future<void> _processAndEvaluateAttempt(String videoPath) async {
    _progressSubscription?.cancel();
    _progressSubscription = videoDataSource.progressStream.listen((update) {
      _processedFrames = update.currentFrame;
      _totalProcessingFrames = update.totalFrames;
      _processingPercent = update.percent.clamp(0.0, 100.0);
      notifyListeners();
    });

    try {
      final frames = await videoDataSource.processVideo(
        videoPath: videoPath,
        fps: 30.0,
      );

      _attemptFrames = frames;
      if (_selectedSign != null) {
        _evaluationResult = evaluatePracticeUseCase.execute(
          referenceSign: _selectedSign!,
          attemptFrames: frames,
        );
      }
      _mode = TeachingMode.practiceResult;
    } catch (e) {
      AppLogger.e('TeachingViewModel: Error evaluando práctica offline', e);
      _errorMessage = 'Error procesando el video con MediaPipe: $e';
      _mode = TeachingMode.practiceReady;
      await cameraDataSource.initializeCamera();
    } finally {
      _progressSubscription?.cancel();
      _progressSubscription = null;
      notifyListeners();
    }
  }

  void _startDemoLoop() {
    _stopDemoLoop();
    final sign = _selectedSign;
    if (sign == null || sign.frames.isEmpty) return;

    final fps = sign.fps > 0 ? sign.fps : 30.0;
    final intervalMs = (1000.0 / (fps * _demoSpeed)).round().clamp(16, 200);

    _demoTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_selectedSign == null || _selectedSign!.frames.isEmpty) return;
      _demoFrameIndex = (_demoFrameIndex + 1) % _selectedSign!.frames.length;
      notifyListeners();
    });
  }

  void _stopDemoLoop() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  Future<void> _cleanupPracticeSession() async {
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _progressSubscription?.cancel();
    _progressSubscription = null;
    await cameraDataSource.disposeCamera();
    await _deleteTempVideo();
    _evaluationResult = null;
    _attemptFrames = const [];
    _errorMessage = null;
  }

  Future<void> _deleteTempVideo() async {
    final path = _attemptTempVideoPath;
    _attemptTempVideoPath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopDemoLoop();
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _progressSubscription?.cancel();
    _deleteTempVideo();
    resolveBodyPoseUseCase.reset();
    super.dispose();
  }
}
