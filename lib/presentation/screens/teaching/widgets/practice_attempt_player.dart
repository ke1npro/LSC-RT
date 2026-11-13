import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/body_pose.dart';
import '../../../../domain/entities/recorded_sign.dart';
import '../../../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../../widgets/painters/body_pose_painter.dart';

class PracticeAttemptPlayer extends StatefulWidget {
  final String videoPath;
  final List<SignFrameLandmarks> frames;

  const PracticeAttemptPlayer({
    super.key,
    required this.videoPath,
    required this.frames,
  });

  @override
  State<PracticeAttemptPlayer> createState() => _PracticeAttemptPlayerState();
}

class _PracticeAttemptPlayerState extends State<PracticeAttemptPlayer> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  int _currentFrameIdx = 0;
  final ResolveBodyPoseUseCase _resolveBodyPose = ResolveBodyPoseUseCase();

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) return;

      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.addListener(_onVideoTick);

      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _isReady = true;
      });
      await ctrl.play();
    } catch (_) {}
  }

  void _onVideoTick() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
    if (widget.frames.isEmpty) return;

    final durMs = _controller!.value.duration.inMilliseconds;
    final posMs = _controller!.value.position.inMilliseconds;
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final idx = (progress * (widget.frames.length - 1)).round().clamp(0, widget.frames.length - 1);

    if (idx != _currentFrameIdx) {
      setState(() => _currentFrameIdx = idx);
    }
  }

  BodyPose? _currentPose(Size size) {
    if (widget.frames.isEmpty) return null;
    final frame = widget.frames[_currentFrameIdx.clamp(0, widget.frames.length - 1)];
    return _resolveBodyPose.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _resolveBodyPose.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final pose = _currentPose(size);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_isReady && _controller != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
                  ),
                ),

              if (pose != null)
                CustomPaint(
                  size: Size.infinite,
                  painter: BodyPosePainter(
                    pose: pose,
                    showOverlay: true,
                    showFace: false,
                    isMirrored: false,
                  ),
                ),

              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Text(
                    'Tu intento (Frame ${_currentFrameIdx + 1}/${widget.frames.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              if (_isReady && _controller != null)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceGlass,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
