import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/offline_video_config.dart';
import '../../core/services/tts_service.dart';
import '../../core/utils/app_logger.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../data/datasources/video_landmarker_datasource.dart';
import '../../domain/entities/body_pose.dart';
import '../../domain/entities/conversation_turn.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/usecases/compose_avatar_response_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../domain/usecases/segment_and_translate_video_usecase.dart';

enum StepConversationPhase {
  readyToRecord,
  countdown,
  recording,
  processing,
  translatedReview,
  composeReply,
  avatarPlayback,
}

class StepConversationViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final VideoLandmarkerDataSource videoDataSource;
  final IDictionaryRepository dictionaryRepository;
  final ISettingsRepository? settingsRepository;
  final ITtsService? ttsService;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;
  final SegmentAndTranslateVideoUseCase segmentAndTranslateUseCase;
  final ComposeAvatarResponseUseCase composeAvatarUseCase;

  StepConversationViewModel({
    required this.cameraDataSource,
    required this.videoDataSource,
    required this.dictionaryRepository,
    this.settingsRepository,
    this.ttsService,
    ResolveBodyPoseUseCase? resolveBodyPoseUseCase,
    SegmentAndTranslateVideoUseCase? segmentAndTranslateUseCase,
    ComposeAvatarResponseUseCase? composeAvatarUseCase,
  })  : resolveBodyPoseUseCase =
            resolveBodyPoseUseCase ?? ResolveBodyPoseUseCase(),
        segmentAndTranslateUseCase =
            segmentAndTranslateUseCase ?? SegmentAndTranslateVideoUseCase(),
        composeAvatarUseCase =
            composeAvatarUseCase ?? ComposeAvatarResponseUseCase() {
    _syncVideoSettings();
  }

  static const double maxRecordingSeconds = 60.0;

  StepConversationPhase _phase = StepConversationPhase.readyToRecord;
  bool _isActiveMode = false;

  // Timers de cuenta regresiva y grabación
  int _countdownSeconds = 3;
  Timer? _countdownTimer;
  double _recordingSeconds = 0.0;
  Timer? _recordingTimer;

  // Progreso offline configurable (FPS & preset de calidad)
  double _processingPercent = 0.0;
  int _processedFrames = 0;
  int _totalProcessingFrames = 0;
  StreamSubscription<VideoProgressUpdate>? _progressSubscription;
  String? _tempVideoPath;
  String _activeQualityPreset = OfflineVideoConfig.defaultPreset;
  int _activeProcessingFps = OfflineVideoConfig.defaultFps;
  int _processingRunId = 0;

  // Traducción Señas -> Texto
  VideoTranslationResult? _lastTranslationResult;

  // Respuesta Texto -> Avatar
  ComposedAvatarResponse? _composedResponse;
  List<SignFrameLandmarks> _activePlaybackFrames = const [];
  List<int> _activeWordStartFrames = const [];
  List<String> _activeWordLabels = const [];
  int _playbackFrameIndex = 0;
  bool _isPlayingAvatar = false;
  double _playbackSpeed = 1.0;
  Timer? _playbackTimer;

  // Historial por turnos de la sesión actual
  final List<ConversationTurn> _history = [];
  bool _isHistoryExpanded = false;
  String? _errorMessage;

  StepConversationPhase get phase => _phase;
  int get countdownSeconds => _countdownSeconds;
  double get recordingSeconds => _recordingSeconds;
  double get processingPercent => _processingPercent;
  int get processedFrames => _processedFrames;
  int get totalProcessingFrames => _totalProcessingFrames;
  String get activeQualityPreset => _activeQualityPreset;
  int get activeProcessingFps => _activeProcessingFps;
  VideoTranslationResult? get lastTranslationResult => _lastTranslationResult;
  ComposedAvatarResponse? get composedResponse => _composedResponse;
  int get playbackFrameIndex => _playbackFrameIndex;
  int get totalPlaybackFrames => _activePlaybackFrames.length;
  bool get isPlayingAvatar => _isPlayingAvatar;
  double get playbackSpeed => _playbackSpeed;
  List<ConversationTurn> get history => List.unmodifiable(_history);
  bool get isHistoryExpanded => _isHistoryExpanded;
  String? get errorMessage => _errorMessage;

  List<RecordedSign> get dictionarySigns => dictionaryRepository.allSigns;

  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;
  bool get isCameraSwitching => cameraDataSource.isSwitching;
  bool get isCameraPermissionDenied => cameraDataSource.isPermissionDenied;
  String? get cameraErrorMessage => cameraDataSource.errorMessage;

  String get currentPlayingWord {
    if (_activeWordLabels.isEmpty || _activeWordStartFrames.isEmpty) return '';
    for (int i = _activeWordStartFrames.length - 1; i >= 0; i--) {
      if (_playbackFrameIndex >= _activeWordStartFrames[i]) {
        return _activeWordLabels[i];
      }
    }
    return _activeWordLabels.first;
  }

  BodyPose? buildCurrentAvatarPose(Size size) {
    if (_activePlaybackFrames.isEmpty) return null;
    final idx = _playbackFrameIndex.clamp(0, _activePlaybackFrames.length - 1);
    final frame = _activePlaybackFrames[idx];
    return resolveBodyPoseUseCase.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  void _syncVideoSettings() {
    _activeQualityPreset = OfflineVideoConfig.sanitizePreset(
      settingsRepository?.offlineQualityPreset ?? OfflineVideoConfig.defaultPreset,
    );
    _activeProcessingFps = OfflineVideoConfig.sanitizeFps(
      settingsRepository?.offlineVideoFps ?? OfflineVideoConfig.defaultFps,
    );
  }

  Future<void> selectQualityPreset(String preset) async {
    final clean = OfflineVideoConfig.sanitizePreset(preset);
    if (clean == _activeQualityPreset &&
        _phase != StepConversationPhase.processing) {
      return;
    }
    _activeQualityPreset = clean;
    await settingsRepository?.setOfflineQualityPreset(clean);
    notifyListeners();

    if (_phase == StepConversationPhase.processing && _tempVideoPath != null) {
      unawaited(_processAndSegmentVideo(_tempVideoPath!));
    }
  }

  Future<void> enterMode() async {
    _isActiveMode = true;
    _errorMessage = null;
    _syncVideoSettings();

    if (!dictionaryRepository.isLoaded) {
      await dictionaryRepository.initialize();
    }
    await ttsService?.initialize();

    if (_phase == StepConversationPhase.readyToRecord) {
      cameraDataSource.setResolutionPreset(ResolutionPreset.high);
      await cameraDataSource.initializeCamera();
    }
    notifyListeners();
  }

  Future<void> leaveMode() async {
    _isActiveMode = false;
    _processingRunId++;
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    _stopAvatarLoop();
    await _deleteTempVideo();
    await cameraDataSource.disposeCamera();
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

  void startCountdown() {
    if (dictionarySigns.isEmpty) {
      _errorMessage =
          'Tu diccionario tiene 0 señas. Graba al menos una en Diccionario primero.';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _phase = StepConversationPhase.countdown;
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
    _phase = StepConversationPhase.recording;
    _recordingSeconds = 0.0;
    notifyListeners();

    try {
      await cameraDataSource.startVideoRecording();

      _recordingTimer?.cancel();
      _recordingTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        _recordingSeconds += 0.1;
        if (_recordingSeconds >= maxRecordingSeconds) {
          timer.cancel();
          stopRecordingAndTranslate();
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      AppLogger.e(
          'StepConversationViewModel: Error iniciando grabación <60s', e);
      _errorMessage = 'No se pudo iniciar la grabación: $e';
      _phase = StepConversationPhase.readyToRecord;
      notifyListeners();
    }
  }

  Future<void> stopRecordingAndTranslate() async {
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    if (_phase != StepConversationPhase.recording) return;

    _syncVideoSettings();
    _phase = StepConversationPhase.processing;
    _processingPercent = 0.0;
    _processedFrames = 0;
    _totalProcessingFrames = 0;
    notifyListeners();

    String? capturedPath;
    try {
      final XFile? videoFile = await cameraDataSource.stopVideoRecording();
      if (videoFile == null) {
        throw Exception('La cámara no guardó el clip de video.');
      }
      capturedPath = videoFile.path;
      _tempVideoPath = capturedPath;
      await cameraDataSource.disposeCamera();
    } catch (e) {
      AppLogger.e(
          'StepConversationViewModel: Error deteniendo grabación <60s', e);
      _errorMessage = 'Error capturando el video: $e';
      _phase = StepConversationPhase.readyToRecord;
      await _deleteTempVideo();
      if (_isActiveMode) {
        await cameraDataSource.initializeCamera();
      }
      notifyListeners();
      return;
    }

    await _processAndSegmentVideo(capturedPath);
  }

  Future<void> _processAndSegmentVideo(String videoPath) async {
    final int runId = ++_processingRunId;
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    _processedFrames = 0;
    _totalProcessingFrames = 0;
    _processingPercent = 0.0;
    notifyListeners();

    _progressSubscription = videoDataSource.progressStream.listen((update) {
      if (runId != _processingRunId) return;
      _processedFrames = update.currentFrame;
      _totalProcessingFrames = update.totalFrames;
      _processingPercent = update.percent.clamp(0.0, 100.0);
      notifyListeners();
    });

    final int targetFps = OfflineVideoConfig.sanitizeFps(
      settingsRepository?.offlineVideoFps ?? _activeProcessingFps,
    );
    _activeProcessingFps = targetFps;
    final int maxDimension =
        OfflineVideoConfig.maxDimensionForPreset(_activeQualityPreset);
    final bool useGpu = settingsRepository?.useGpuDelegate ?? false;

    try {
      final frames = await videoDataSource.processVideo(
        videoPath: videoPath,
        fps: targetFps.toDouble(),
        maxDimension: maxDimension,
        useGpu: useGpu,
      );

      if (runId != _processingRunId) return;

      final result = segmentAndTranslateUseCase.execute(
        recordedFrames: frames,
        dictionarySigns: dictionaryRepository.allSigns,
      );

      _lastTranslationResult = result;
      if (result.hasTranslation) {
        _history.add(
          ConversationTurn(
            id: 'turn_sign_${DateTime.now().millisecondsSinceEpoch}',
            timestamp: DateTime.now(),
            isFromSigner: true,
            text: result.fullText,
            segments: result.segments,
          ),
        );
      }

      _phase = StepConversationPhase.translatedReview;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED' || runId != _processingRunId) return;
      AppLogger.e('StepConversationViewModel: Error procesando grabación', e);
      _errorMessage = 'Error al procesar el video: ${e.message ?? e.code}';
      _phase = StepConversationPhase.readyToRecord;
      if (_isActiveMode) {
        await cameraDataSource.initializeCamera();
      }
    } catch (e) {
      if (runId != _processingRunId) return;
      AppLogger.e('StepConversationViewModel: Error procesando grabación', e);
      _errorMessage = 'Error al procesar el video: $e';
      _phase = StepConversationPhase.readyToRecord;
      if (_isActiveMode) {
        await cameraDataSource.initializeCamera();
      }
    } finally {
      if (runId == _processingRunId) {
        await _progressSubscription?.cancel();
        _progressSubscription = null;
        await _deleteTempVideo();
        notifyListeners();
      }
    }
  }

  Future<void> speakTranslatedText() async {
    final text = _lastTranslationResult?.fullText ?? '';
    if (text.trim().isEmpty) return;
    await ttsService?.speak(text);
  }

  void proceedToComposeReply() {
    _errorMessage = null;
    _phase = StepConversationPhase.composeReply;
    notifyListeners();
  }

  void submitReplyText(String text) {
    final clean = text.trim();
    if (clean.isEmpty) {
      _errorMessage = 'Escribe una respuesta para convertirla a señas.';
      notifyListeners();
      return;
    }
    _errorMessage = null;

    final response = composeAvatarUseCase.execute(
      text: clean,
      dictionarySigns: dictionaryRepository.allSigns,
    );

    _composedResponse = response;
    final matchedWords = response.matchedSigns.map((s) => s.word).toList();

    _history.add(
      ConversationTurn(
        id: 'turn_reply_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        isFromSigner: false,
        text: clean,
        matchedWords: matchedWords,
        missingWords: response.missingWords,
        avatarFrames: response.frames,
        wordStartFrames: response.wordStartFrames,
      ),
    );

    _loadPlaybackSequence(
      frames: response.frames,
      wordStartFrames: response.wordStartFrames,
      wordLabels: matchedWords,
    );
    _phase = StepConversationPhase.avatarPlayback;
    notifyListeners();
  }

  void _loadPlaybackSequence({
    required List<SignFrameLandmarks> frames,
    required List<int> wordStartFrames,
    required List<String> wordLabels,
  }) {
    _stopAvatarLoop();
    resolveBodyPoseUseCase.reset();
    _activePlaybackFrames = frames;
    _activeWordStartFrames = wordStartFrames;
    _activeWordLabels = wordLabels;
    _playbackFrameIndex = 0;
    if (frames.isNotEmpty) {
      _startAvatarLoop();
    }
  }

  void _startAvatarLoop() {
    _playbackTimer?.cancel();
    if (_activePlaybackFrames.isEmpty) return;

    _isPlayingAvatar = true;
    final intervalMs = (33.0 / _playbackSpeed).round().clamp(16, 120);
    _playbackTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_activePlaybackFrames.isEmpty) return;
      _playbackFrameIndex =
          (_playbackFrameIndex + 1) % _activePlaybackFrames.length;
      notifyListeners();
    });
  }

  void _stopAvatarLoop() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlayingAvatar = false;
  }

  void toggleAvatarPlayPause() {
    if (_activePlaybackFrames.isEmpty) return;
    if (_isPlayingAvatar) {
      _stopAvatarLoop();
    } else {
      _startAvatarLoop();
    }
    notifyListeners();
  }

  void cyclePlaybackSpeed() {
    if (_playbackSpeed == 1.0) {
      _playbackSpeed = 0.5;
    } else if (_playbackSpeed == 0.5) {
      _playbackSpeed = 1.5;
    } else {
      _playbackSpeed = 1.0;
    }
    if (_isPlayingAvatar) {
      _startAvatarLoop();
    }
    notifyListeners();
  }

  void replayHistoryTurn(ConversationTurn turn) {
    if (turn.isFromSigner) {
      ttsService?.speak(turn.text);
      return;
    }
    if (!turn.hasReplayableAvatar) return;

    _composedResponse = ComposedAvatarResponse(
      originalText: turn.text,
      matchedSigns: const [],
      missingWords: turn.missingWords,
      frames: turn.avatarFrames,
      wordStartFrames: turn.wordStartFrames,
    );
    _loadPlaybackSequence(
      frames: turn.avatarFrames,
      wordStartFrames: turn.wordStartFrames,
      wordLabels: turn.matchedWords,
    );
    _phase = StepConversationPhase.avatarPlayback;
    notifyListeners();
  }

  Future<void> startNextTurn() async {
    _stopAvatarLoop();
    _syncVideoSettings();
    _lastTranslationResult = null;
    _composedResponse = null;
    _activePlaybackFrames = const [];
    _activeWordStartFrames = const [];
    _activeWordLabels = const [];
    _errorMessage = null;
    _phase = StepConversationPhase.readyToRecord;
    notifyListeners();

    if (_isActiveMode) {
      cameraDataSource.setResolutionPreset(ResolutionPreset.high);
      await cameraDataSource.initializeCamera();
      notifyListeners();
    }
  }

  void toggleHistoryExpanded() {
    _isHistoryExpanded = !_isHistoryExpanded;
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _isHistoryExpanded = false;
    notifyListeners();
  }

  Future<void> _deleteTempVideo() async {
    final path = _tempVideoPath;
    _tempVideoPath = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _processingRunId++;
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _progressSubscription?.cancel();
    _stopAvatarLoop();
    _deleteTempVideo();
    resolveBodyPoseUseCase.reset();
    super.dispose();
  }
}
