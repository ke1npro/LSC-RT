import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/app_logger.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../data/datasources/video_landmarker_datasource.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/entities/sign_take_candidate.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../../domain/usecases/select_best_take_usecase.dart';

enum WizardStep {
  setup,
  cameraPreview,
  countdown,
  recording,
  processing,
  trimReview,
  takesSummary,
}

class SignRecorderViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final VideoLandmarkerDataSource videoDataSource;
  final IDictionaryRepository dictionaryRepository;
  final SelectBestTakeUseCase selectBestTakeUseCase;

  SignRecorderViewModel({
    required this.cameraDataSource,
    required this.videoDataSource,
    required this.dictionaryRepository,
    SelectBestTakeUseCase? selectBestTakeUseCase,
  }) : selectBestTakeUseCase = selectBestTakeUseCase ?? SelectBestTakeUseCase();

  WizardStep _step = WizardStep.setup;
  String _word = '';
  String _category = 'General';
  int _requiredHands = 1; // 1 o 2

  final List<SignTakeCandidate> _takes = [];
  int _activeTakeIndex = 0;

  // Countdown & Recording timer
  int _countdownSeconds = 3;
  Timer? _countdownTimer;
  double _recordingSeconds = 0.0;
  Timer? _recordingTimer;
  static const double maxRecordingSeconds = 6.0;

  // Processing progress
  double _processingPercent = 0.0;
  int _processedFrames = 0;
  int _totalProcessingFrames = 0;
  StreamSubscription<VideoProgressUpdate>? _progressSubscription;

  // Status & Errors
  bool _isBusy = false;
  String? _errorMessage;

  WizardStep get step => _step;
  String get word => _word;
  String get category => _category;
  int get requiredHands => _requiredHands;
  List<SignTakeCandidate> get takes => List.unmodifiable(_takes);
  int get activeTakeIndex => _activeTakeIndex;
  SignTakeCandidate? get activeTake =>
      (_takes.isNotEmpty && _activeTakeIndex < _takes.length)
          ? _takes[_activeTakeIndex]
          : null;

  int get countdownSeconds => _countdownSeconds;
  double get recordingSeconds => _recordingSeconds;
  double get processingPercent => _processingPercent;
  int get processedFrames => _processedFrames;
  int get totalProcessingFrames => _totalProcessingFrames;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  BestTakeEvaluationResult? get bestEvaluation {
    if (_takes.isEmpty) return null;
    return selectBestTakeUseCase.execute(
      takes: _takes,
      requiredHands: _requiredHands,
    );
  }

  void initSetup({
    String initialWord = '',
    String initialCategory = 'General',
    int initialHands = 1,
  }) {
    _word = initialWord;
    _category = initialCategory;
    _requiredHands = initialHands;
    _step = WizardStep.setup;
    _takes.clear();
    _activeTakeIndex = 0;
    _errorMessage = null;
    notifyListeners();
  }

  void updateMetadata({
    String? word,
    String? category,
    int? requiredHands,
  }) {
    if (word != null) _word = word.trim().toUpperCase();
    if (category != null) _category = category.trim();
    if (requiredHands != null) _requiredHands = requiredHands.clamp(1, 2);
    notifyListeners();
  }

  Future<void> proceedToCamera() async {
    if (_word.trim().isEmpty) {
      _errorMessage = 'Por favor ingresa el nombre de la seña';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    _step = WizardStep.cameraPreview;
    notifyListeners();

    cameraDataSource.setResolutionPreset(ResolutionPreset.high);
    await cameraDataSource.initializeCamera();
    notifyListeners();
  }

  void startCountdown() {
    _step = WizardStep.countdown;
    _countdownSeconds = 3;
    notifyListeners();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _startRecording();
      }
    });
  }

  Future<void> _startRecording() async {
    _step = WizardStep.recording;
    _recordingSeconds = 0.0;
    notifyListeners();

    try {
      await cameraDataSource.startVideoRecording();

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        _recordingSeconds += 0.1;
        if (_recordingSeconds >= maxRecordingSeconds) {
          timer.cancel();
          stopRecording();
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      AppLogger.e('SignRecorderViewModel: Error iniciando grabación', e);
      _errorMessage = 'No se pudo iniciar la grabación de video: $e';
      _step = WizardStep.cameraPreview;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();

    if (_step != WizardStep.recording) return;

    _step = WizardStep.processing;
    _processingPercent = 0.0;
    _processedFrames = 0;
    _totalProcessingFrames = 0;
    notifyListeners();

    try {
      final XFile? videoFile = await cameraDataSource.stopVideoRecording();
      if (videoFile == null) {
        throw Exception('El video no fue guardado por la cámara');
      }

      await _processOfflineVideo(videoFile.path);
    } catch (e) {
      AppLogger.e('SignRecorderViewModel: Error al detener grabación', e);
      _errorMessage = 'Error capturando el video: $e';
      _step = WizardStep.cameraPreview;
      notifyListeners();
    }
  }

  Future<void> _processOfflineVideo(String videoPath) async {
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

      final durationMs = frames.isNotEmpty ? frames.last.timestampMs : 0;
      final newTake = SignTakeCandidate(
        takeNumber: _takes.length + 1,
        tempVideoPath: videoPath,
        allFrames: frames,
        videoDurationMs: durationMs,
        trimStartFrame: 0,
        trimEndFrame: frames.isEmpty ? 0 : frames.length - 1,
      );

      _takes.add(newTake);
      _activeTakeIndex = _takes.length - 1;
      _step = WizardStep.trimReview;
    } catch (e) {
      AppLogger.e('SignRecorderViewModel: Error en procesamiento offline', e);
      _errorMessage = 'Error al procesar el video con MediaPipe: $e';
      _step = WizardStep.cameraPreview;
    } finally {
      _progressSubscription?.cancel();
      _progressSubscription = null;
      notifyListeners();
    }
  }

  void updateActiveTakeTrim(int startFrame, int endFrame) {
    if (_takes.isEmpty || _activeTakeIndex >= _takes.length) return;
    final current = _takes[_activeTakeIndex];
    _takes[_activeTakeIndex] = current.copyWith(
      trimStartFrame: startFrame,
      trimEndFrame: endFrame,
    );
    notifyListeners();
  }

  void viewTakesSummary() {
    _step = WizardStep.takesSummary;
    notifyListeners();
  }

  void selectTakeForReview(int index) {
    if (index >= 0 && index < _takes.length) {
      _activeTakeIndex = index;
      _step = WizardStep.trimReview;
      notifyListeners();
    }
  }

  Future<void> recordAnotherTake() async {
    if (_takes.length >= 5) {
      _errorMessage = 'Has alcanzado el límite máximo de 5 tomas';
      notifyListeners();
      return;
    }
    _step = WizardStep.cameraPreview;
    notifyListeners();
    await cameraDataSource.initializeCamera();
    notifyListeners();
  }

  Future<RecordedSign?> finishAndSave() async {
    final eval = bestEvaluation;
    if (eval == null) {
      _errorMessage = 'No hay tomas registradas';
      notifyListeners();
      return null;
    }

    if (!eval.isAcceptable) {
      _errorMessage =
          'Ninguna toma alcanzó el umbral mínimo de calidad del ${(eval.threshold * 100).toInt()}% de detección de manos. Vuelve a intentar o graba una nueva toma.';
      notifyListeners();
      return null;
    }

    _isBusy = true;
    notifyListeners();

    try {
      final winner = eval.winner;
      final trimmed = winner.trimmedFrames;

      final sign = RecordedSign(
        id: '${_word.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}_${DateTime.now().millisecondsSinceEpoch}',
        word: _word,
        category: _category,
        requiredHands: _requiredHands,
        fps: 30.0,
        detectionRate: eval.bestRate,
        averageConfidence: eval.bestConfidence,
        totalTakesEvaluated: _takes.length,
        createdAt: DateTime.now(),
        frames: trimmed,
      );

      await dictionaryRepository.saveRecordedSign(sign);

      // Eliminar TODOS los videos temporales .mp4 para no consumir almacenamiento
      await _cleanupTempFiles();

      _step = WizardStep.setup;
      _takes.clear();
      _activeTakeIndex = 0;
      return sign;
    } catch (e) {
      AppLogger.e('SignRecorderViewModel: Error guardando seña', e);
      _errorMessage = 'Error al guardar la seña: $e';
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> cancelAndCleanup() async {
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _progressSubscription?.cancel();
    await _cleanupTempFiles();
    await cameraDataSource.disposeCamera();
    _step = WizardStep.setup;
    _takes.clear();
    _activeTakeIndex = 0;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _cleanupTempFiles() async {
    for (final take in _takes) {
      try {
        final f = File(take.tempVideoPath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _progressSubscription?.cancel();
    _cleanupTempFiles();
    super.dispose();
  }
}
