import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../data/datasources/avatar_motion_datasource.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../domain/entities/avatar_sign_data.dart';
import '../../domain/entities/body_pose.dart';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../../domain/usecases/evaluate_posture_usecase.dart';
import '../../domain/usecases/generate_wave_guide_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

enum TeachingMode {
  catalog,
  demonstration,
  practice,
}

class TeachingViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final IVisionRepository visionRepository;
  final ISettingsRepository? settingsRepository;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;
  final GenerateWaveGuideUseCase generateWaveGuideUseCase;
  final EvaluatePostureUseCase evaluatePostureUseCase;
  final AvatarMotionDataSource avatarMotionDataSource;

  StreamSubscription? _handSubscription;
  StreamSubscription? _faceSubscription;

  List<HandPose> _rawHands = [];
  List<FaceBounds> _rawFaces = [];
  Size? _viewportSize;

  bool _isInitialized = false;
  TeachingMode _mode = TeachingMode.catalog;
  AvatarSignData? _selectedSign;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';

  // Animación del Avatar Demostrativo
  int _demoFrameIndex = 0;
  Timer? _demoTimer;

  // Estado del usuario en práctica
  double _animationProgress = 0.0;
  BodyPose? _userPose;
  BodyPose? _guidePose;
  double _matchScore = 0.0;

  TeachingViewModel({
    required this.cameraDataSource,
    required this.visionRepository,
    this.settingsRepository,
    required this.resolveBodyPoseUseCase,
    required this.generateWaveGuideUseCase,
    required this.evaluatePostureUseCase,
    required this.avatarMotionDataSource,
  });

  bool get isInitialized => _isInitialized;
  TeachingMode get mode => _mode;
  AvatarSignData? get selectedSign => _selectedSign;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  int get demoFrameIndex => _demoFrameIndex;
  BodyPose? get userPose => _userPose;
  BodyPose? get guidePose => _guidePose;
  double get matchScore => _matchScore;
  double get animationProgress => _animationProgress;
  bool get hasUserHand => _userPose?.hasHand ?? false;
  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;

  bool get isCameraSwitching => cameraDataSource.isSwitching;
  bool get isCameraPermissionDenied => cameraDataSource.isPermissionDenied;
  String? get cameraErrorMessage => cameraDataSource.errorMessage;

  AvatarFrame? get currentDemoFrame {
    if (_selectedSign == null || _selectedSign!.frames.isEmpty) return null;
    final idx = _demoFrameIndex.clamp(0, _selectedSign!.frames.length - 1);
    return _selectedSign!.frames[idx];
  }

  List<String> get categories => ['Todos', ...avatarMotionDataSource.getCategories()];

  List<AvatarSignData> get filteredSigns {
    var signs = avatarMotionDataSource.allSigns;
    if (_selectedCategory != 'Todos') {
      signs = signs.where((s) => s.category == _selectedCategory).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      signs = signs.where((s) {
        return s.displayName.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q);
      }).toList();
    }
    return signs;
  }

  Future<void> initialize() async {
    await avatarMotionDataSource.initialize();
    await visionRepository.initialize();
    visionRepository.setRotation(settingsRepository?.modelRotationDegrees ?? 270);

    await _handSubscription?.cancel();
    _handSubscription = visionRepository.handStream.listen(_onHandsDetected);

    await _faceSubscription?.cancel();
    _faceSubscription = visionRepository.faceStream.listen(_onFacesDetected);

    _isInitialized = true;
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

  void selectSign(AvatarSignData sign) {
    _selectedSign = sign;
    _mode = TeachingMode.demonstration;
    _demoFrameIndex = 0;
    _startDemoLoop();
    notifyListeners();
  }

  void backToCatalog() {
    _stopDemoLoop();
    _selectedSign = null;
    _mode = TeachingMode.catalog;
    notifyListeners();
  }

  void backToDemonstration() {
    _mode = TeachingMode.demonstration;
    _startDemoLoop();
    notifyListeners();
  }

  Future<void> startPractice() async {
    _stopDemoLoop();
    _mode = TeachingMode.practice;
    _matchScore = 0.0;
    notifyListeners();

    // Inicializar cámara si aún no está activa
    if (!cameraDataSource.isInitialized) {
      await cameraDataSource.initializeCamera(
        onFrame: (image, orientation) {
          visionRepository.processFrame(image, orientation);
        },
      );
    }
    _startPracticeLoop();
    notifyListeners();
  }

  void _startDemoLoop() {
    _stopDemoLoop();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 42), (_) {
      if (_selectedSign == null || _selectedSign!.frames.isEmpty) return;
      _demoFrameIndex = (_demoFrameIndex + 1) % _selectedSign!.frames.length;
      notifyListeners();
    });
  }

  void _startPracticeLoop() {
    _stopDemoLoop();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 42), (_) {
      if (_selectedSign == null || _selectedSign!.frames.isEmpty) return;
      _demoFrameIndex = (_demoFrameIndex + 1) % _selectedSign!.frames.length;
      _recomputeScore();
      notifyListeners();
    });
  }

  void _stopDemoLoop() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  Future<void> retryCamera() async {
    notifyListeners();
    await cameraDataSource.initializeCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );
    notifyListeners();
  }

  void setViewportSize(Size size) {
    if (_viewportSize == size) return;
    _viewportSize = size;
    _recomputeUserPose();
    _updateGuidePose();
    _recomputeScore();
  }

  Future<void> switchCamera() async {
    if (cameraDataSource.cameras.length < 2 || cameraDataSource.isSwitching) return;
    resolveBodyPoseUseCase.reset();
    _userPose = null;
    notifyListeners();

    await cameraDataSource.switchCamera(
      onFrame: (image, orientation) {
        visionRepository.processFrame(image, orientation);
      },
    );
    notifyListeners();
  }

  void updateAnimation(double progress) {
    _animationProgress = progress;
    _updateGuidePose();
    _recomputeScore();
    notifyListeners();
  }

  void _onHandsDetected(List<HandPose> hands) {
    _rawHands = hands;
    _recomputeUserPose();
    _recomputeScore();
    notifyListeners();
  }

  void _onFacesDetected(List<FaceBounds> faces) {
    _rawFaces = faces;
    _recomputeUserPose();
    _recomputeScore();
    notifyListeners();
  }

  void _recomputeUserPose() {
    final size = _viewportSize ?? const Size(400, 600);
    _userPose = resolveBodyPoseUseCase.execute(
      hands: _rawHands,
      faces: _rawFaces,
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  void _updateGuidePose() {
    final width = _viewportSize?.width ?? 400.0;
    _guidePose = generateWaveGuideUseCase.execute(
      animationProgress: _animationProgress,
      viewportWidth: width,
    );
  }

  void _recomputeScore() {
    if (_userPose == null) {
      _matchScore = 0.0;
      return;
    }

    _matchScore = evaluatePostureUseCase.execute(
      userPose: _userPose!,
      guidePose: _guidePose,
      referenceFrame: currentDemoFrame,
      animationProgress: _animationProgress,
    );
  }

  @override
  void dispose() {
    _stopDemoLoop();
    _handSubscription?.cancel();
    _faceSubscription?.cancel();
    resolveBodyPoseUseCase.reset();
    super.dispose();
  }
}
