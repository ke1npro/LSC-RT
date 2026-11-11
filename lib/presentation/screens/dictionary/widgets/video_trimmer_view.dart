import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/body_pose.dart';
import '../../../../domain/entities/sign_take_candidate.dart';
import '../../../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../../widgets/painters/body_pose_painter.dart';

class VideoTrimmerView extends StatefulWidget {
  final SignTakeCandidate candidate;
  final int requiredHands;
  final Function(int startFrame, int endFrame) onTrimChanged;

  const VideoTrimmerView({
    super.key,
    required this.candidate,
    required this.requiredHands,
    required this.onTrimChanged,
  });

  @override
  State<VideoTrimmerView> createState() => _VideoTrimmerViewState();
}

class _VideoTrimmerViewState extends State<VideoTrimmerView> {
  VideoPlayerController? _controller;
  bool _isPlayerInitialized = false;
  late RangeValues _rangeValues;
  final ResolveBodyPoseUseCase _resolveBodyPose = ResolveBodyPoseUseCase();
  int _currentFrameIndex = 0;

  @override
  void initState() {
    super.initState();
    final maxIdx = (widget.candidate.totalRawFrames > 0)
        ? (widget.candidate.totalRawFrames - 1).toDouble()
        : 0.0;
    _rangeValues = RangeValues(
      widget.candidate.trimStartFrame.toDouble().clamp(0.0, maxIdx),
      widget.candidate.trimEndFrame.toDouble().clamp(0.0, maxIdx),
    );
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      final file = File(widget.candidate.tempVideoPath);
      if (!await file.exists()) return;

      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      ctrl.setLooping(true);

      ctrl.addListener(_onVideoUpdate);

      if (mounted) {
        setState(() {
          _controller = ctrl;
          _isPlayerInitialized = true;
        });
        ctrl.play();
      }
    } catch (_) {}
  }

  void _onVideoUpdate() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    final posMs = _controller!.value.position.inMilliseconds;
    final totalFrames = widget.candidate.totalRawFrames;
    if (totalFrames == 0) return;

    // Calcular frame correspondiente
    final durMs = _controller!.value.duration.inMilliseconds;
    final double progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final frameIdx = (progress * (totalFrames - 1)).round();

    // Restricción de bucle dentro del rango recortado
    final startMs = (_rangeValues.start / totalFrames) * durMs;
    final endMs = (_rangeValues.end / totalFrames) * durMs;

    if (posMs > endMs && endMs > startMs) {
      _controller!.seekTo(Duration(milliseconds: startMs.toInt()));
    } else if (posMs < startMs) {
      _controller!.seekTo(Duration(milliseconds: startMs.toInt()));
    }

    if (frameIdx != _currentFrameIndex && mounted) {
      setState(() {
        _currentFrameIndex = frameIdx.clamp(0, totalFrames - 1);
      });
    }
  }

  BodyPose? _getCurrentPose(Size size) {
    if (widget.candidate.allFrames.isEmpty) return null;
    final safeIdx = _currentFrameIndex.clamp(0, widget.candidate.allFrames.length - 1);
    final frame = widget.candidate.allFrames[safeIdx];

    return _resolveBodyPose.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxFrames = widget.candidate.totalRawFrames;
    final startFrame = _rangeValues.start.round();
    final endFrame = _rangeValues.end.round();
    final candidateWithTrim = widget.candidate.copyWith(
      trimStartFrame: startFrame,
      trimEndFrame: endFrame,
    );

    final validCount = candidateWithTrim.validFramesCount(widget.requiredHands);
    final totalTrimmed = candidateWithTrim.trimmedFramesCount;
    final rate = candidateWithTrim.detectionRate(widget.requiredHands);
    final pct = (rate * 100).toStringAsFixed(1);
    final isPassing = rate >= 0.70;

    return Column(
      children: [
        // 1. Visor de Video con Overlay de MediaPipe en vivo
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPassing
                    ? AppColors.cyanAccent.withValues(alpha: 0.5)
                    : Colors.amber.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final pose = _getCurrentPose(size);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isPlayerInitialized && _controller != null)
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

                    // MediaPipe HandLandmarker Skeleton Overlay
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

                    // Badge de Fotograma actual en esquina superior
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          'Frame $_currentFrameIndex / ${maxFrames > 0 ? maxFrames - 1 : 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Botón Play / Pausa centrado inferior
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceGlass,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(
                          (_controller?.value.isPlaying ?? false)
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        onPressed: () {
                          if (_controller == null) return;
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
          ),
        ),

        const SizedBox(height: 12),

        // 2. Indicador en Vivo de Reconocimiento de Manos
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isPassing
                ? AppColors.cyanAccent.withValues(alpha: 0.12)
                : Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPassing ? AppColors.cyanAccent : Colors.amber,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isPassing ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: isPassing ? AppColors.cyanAccent : Colors.amber,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconocimiento: $validCount / $totalTrimmed frames ($pct%)',
                      style: TextStyle(
                        color: isPassing ? AppColors.cyanAccent : Colors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPassing
                          ? 'Muestra apta para el diccionario (mínimo 70%)'
                          : 'Baja detección en el recorte. Ajusta inicio/fin o vuelve a grabar.',
                      style: TextStyle(
                        color: isPassing
                            ? AppColors.textSecondary
                            : Colors.amber.shade200,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 3. Recortador Interactivo de Inicio y Fin
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inicio: Frame $startFrame',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Duración: $totalTrimmed frames (~${(totalTrimmed / 30.0).toStringAsFixed(1)}s)',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Fin: Frame $endFrame',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (maxFrames > 1)
                RangeSlider(
                  values: _rangeValues,
                  min: 0.0,
                  max: (maxFrames - 1).toDouble(),
                  divisions: (maxFrames - 1) < 1 ? 1 : (maxFrames - 1),
                  activeColor: isPassing ? AppColors.cyanAccent : Colors.amber,
                  inactiveColor: AppColors.glassBorder,
                  onChanged: (RangeValues newValues) {
                    setState(() {
                      _rangeValues = newValues;
                    });
                    widget.onTrimChanged(
                      newValues.start.round(),
                      newValues.end.round(),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
