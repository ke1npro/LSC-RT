import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../data/datasources/camera_datasource.dart';
import '../../domain/entities/body_pose.dart';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../../domain/usecases/evaluate_posture_usecase.dart';
import '../../domain/usecases/generate_wave_guide_usecase.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

class TeachingViewModel extends ChangeNotifier {
  final CameraDataSource cameraDataSource;
  final IVisionRepository visionRepository;
  final ISettingsRepository? settingsRepository;
  final ResolveBodyPoseUseCase resolveBodyPoseUseCase;
  final GenerateWaveGuideUseCase generateWaveGuideUseCase;
  final EvaluatePostureUseCase evaluatePostureUseCase;

  StreamSubscription? _handSubscription;
  StreamSubscription? _faceSubscription;

  List<HandPose> _rawHands = [];
  List<FaceBounds> _rawFaces = [];
  Size? _viewportSize;

  bool _isInitialized = false;
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
  });

  bool get isInitialized => _isInitialized;
  BodyPose? get userPose => _userPose;
  BodyPose? get guidePose => _guidePose;
  double get matchScore => _matchScore;
  double get animationProgress => _animationProgress;
  bool get hasUserHand => _userPose?.hasHand ?? false;
  bool get isFrontCamera =>
      cameraDataSource.currentCamera?.lensDirection ==
      CameraLensDirection.front;

  Future<void> initialize() async {
    await visionRepository.initialize();
    visionRepository.setRotation(settingsRepository?.modelRotationDegrees ?? 90);

    await _handSubscription?.cancel();
    _handSubscription = visionRepository.handStream.listen(_onHandsDetected);

    await _faceSubscription?.cancel();
    _faceSubscription = visionRepository.faceStream.listen(_onFacesDetected);

    if (cameraDataSource.cameras.isNotEmpty) {
      try {
        await cameraDataSource.initializeCamera(
          onFrame: (image, orientation) {
            visionRepository.processFrame(image, orientation);
          },
        );
        _isInitialized = true;
      } catch (e) {
        debugPrint('Error inicializando cámara en TeachingViewModel: $e');
      }
    }

    _updateGuidePose();
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
    if (cameraDataSource.cameras.length < 2) return;
    resolveBodyPoseUseCase.reset();
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
    if (_userPose == null || _guidePose == null) {
      _matchScore = 0.0;
      return;
    }
    _matchScore = evaluatePostureUseCase.execute(
      userPose: _userPose!,
      guidePose: _guidePose!,
      animationProgress: _animationProgress,
    );
  }

  @override
  void dispose() {
    _handSubscription?.cancel();
    _faceSubscription?.cancel();
    resolveBodyPoseUseCase.reset();
    super.dispose();
  }
}
