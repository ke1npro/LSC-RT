import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/body_pose.dart';
import '../../../../domain/entities/recorded_sign.dart';
import '../../../../domain/entities/sign_take_candidate.dart';
import '../../../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../../widgets/painters/body_pose_painter.dart';

enum _TrimmerDragTarget { start, end, playhead }

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
  late int _startFrame;
  late int _endFrame;
  int _currentFrameIndex = 0;
  int _extraQuarterTurns = 0;

  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  DateTime _lastLoopSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScrubSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  final ResolveBodyPoseUseCase _resolveBodyPose = ResolveBodyPoseUseCase();

  @override
  void initState() {
    super.initState();
    final maxIdx = math.max(0, widget.candidate.totalRawFrames - 1);
    _startFrame = widget.candidate.trimStartFrame.clamp(0, maxIdx);
    _endFrame = widget.candidate.trimEndFrame.clamp(_startFrame, maxIdx);
    _currentFrameIndex = _startFrame;
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      final file = File(widget.candidate.tempVideoPath);
      if (!await file.exists()) return;

      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      await ctrl.setLooping(true);
      ctrl.addListener(_onVideoUpdate);

      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _isPlayerInitialized = true;
      });
      await ctrl.play();
    } catch (_) {}
  }

  int _effectiveDurationMs() {
    final ctrlMs = _controller?.value.duration.inMilliseconds ?? 0;
    if (ctrlMs > 0) return ctrlMs;
    return math.max(1, widget.candidate.videoDurationMs);
  }

  int _frameToMs(int frame) {
    final totalFrames = widget.candidate.totalRawFrames;
    final durMs = _effectiveDurationMs();
    if (totalFrames <= 1 || durMs <= 0) return 0;
    final ratio = (frame.clamp(0, totalFrames - 1)) / (totalFrames - 1);
    return (ratio * durMs).round();
  }

  int _msToFrame(int posMs) {
    final totalFrames = widget.candidate.totalRawFrames;
    final durMs = _effectiveDurationMs();
    if (totalFrames <= 1 || durMs <= 0) return 0;
    final ratio = (posMs / durMs).clamp(0.0, 1.0);
    return (ratio * (totalFrames - 1)).round().clamp(0, totalFrames - 1);
  }

  void _onVideoUpdate() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    final totalFrames = widget.candidate.totalRawFrames;
    if (totalFrames <= 0) return;

    final posMs = _controller!.value.position.inMilliseconds;
    final frameIdx = _msToFrame(posMs);

    if (frameIdx != _currentFrameIndex && mounted) {
      setState(() {
        _currentFrameIndex = frameIdx;
      });
    }

    // No auto-seek mientras el usuario arrastra los tiradores ni hacia atras desde startMs,
    // porque ExoPlayer ajusta seekTo al sync-frame anterior (< startMs) y congelaria el loop.
    if (_isScrubbing) return;

    final startMs = _frameToMs(_startFrame);
    final endMs = _frameToMs(_endFrame);
    if (endMs > startMs && posMs >= endMs) {
      final now = DateTime.now();
      if (now.difference(_lastLoopSeekAt).inMilliseconds >= 250) {
        _lastLoopSeekAt = now;
        _controller!.seekTo(Duration(milliseconds: startMs));
      }
    }
  }

  Future<void> _seekToFrame(int frame) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final targetMs = _frameToMs(frame);
    await ctrl.seekTo(Duration(milliseconds: targetMs));
  }

  void _handleScrubStart(_TrimmerDragTarget target) {
    final ctrl = _controller;
    _wasPlayingBeforeScrub = ctrl?.value.isPlaying ?? false;
    _isScrubbing = true;
    ctrl?.pause();
  }

  void _handleScrubUpdate(_TrimmerDragTarget target, int newStart, int newEnd, int newPlayhead) {
    final trimChanged = newStart != _startFrame || newEnd != _endFrame;
    setState(() {
      _startFrame = newStart;
      _endFrame = newEnd;
      _currentFrameIndex = newPlayhead;
    });
    if (trimChanged) {
      widget.onTrimChanged(_startFrame, _endFrame);
    }

    final now = DateTime.now();
    if (now.difference(_lastScrubSeekAt).inMilliseconds >= 60) {
      _lastScrubSeekAt = now;
      _seekToFrame(newPlayhead);
    }
  }

  Future<void> _handleScrubEnd(_TrimmerDragTarget target) async {
    _isScrubbing = false;
    final seekFrame =
        target == _TrimmerDragTarget.start ? _startFrame : _currentFrameIndex;
    await _seekToFrame(seekFrame);
    if (mounted && _wasPlayingBeforeScrub) {
      await _controller?.play();
    }
  }

  void _handleTapPlayhead(int tappedFrame) {
    final clamped = tappedFrame.clamp(_startFrame, _endFrame);
    setState(() {
      _currentFrameIndex = clamped;
    });
    _seekToFrame(clamped);
  }

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      } else {
        if (_currentFrameIndex >= _endFrame) {
          _seekToFrame(_startFrame);
        }
        ctrl.play();
      }
    });
  }

  BodyPose? _getCurrentPose(Size size) {
    if (widget.candidate.allFrames.isEmpty) return null;
    final safeIdx =
        _currentFrameIndex.clamp(0, widget.candidate.allFrames.length - 1);
    final frame = widget.candidate.allFrames[safeIdx];

    return _resolveBodyPose.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  String _formatSeconds(int frame) {
    final totalFrames = widget.candidate.totalRawFrames;
    final durMs = _effectiveDurationMs();
    if (totalFrames <= 1 || durMs <= 0) return '0.0s';
    final sec = (frame.clamp(0, totalFrames - 1) / (totalFrames - 1)) *
        (durMs / 1000.0);
    return '${sec.toStringAsFixed(1)}s';
  }

  String _formatTrimDuration() {
    final totalFrames = widget.candidate.totalRawFrames;
    final durMs = _effectiveDurationMs();
    if (totalFrames <= 1 || durMs <= 0) return '0.0s';
    final span = math.max(0, _endFrame - _startFrame);
    final sec = (span / (totalFrames - 1)) * (durMs / 1000.0);
    return '${sec.toStringAsFixed(1)}s';
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
    final candidateWithTrim = widget.candidate.copyWith(
      trimStartFrame: _startFrame,
      trimEndFrame: _endFrame,
    );

    final validCount =
        candidateWithTrim.validFramesCount(widget.requiredHands);
    final totalTrimmed = candidateWithTrim.trimmedFramesCount;
    final rate = candidateWithTrim.detectionRate(widget.requiredHands);
    final pct = (rate * 100).toStringAsFixed(1);
    final isPassing = rate >= 0.70;
    final isPlaying = _controller?.value.isPlaying ?? false;

    return Column(
      children: [
        // 1. Visor de Video con correccion de rotacion, tap-to-play y overlay de MediaPipe
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayPause,
                  child: _buildVideoWithOverlay(),
                ),

                if (_isPlayerInitialized && !isPlaying)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                          border: Border.all(color: Colors.white54, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),

                // Badge de Fotograma actual en esquina superior izquierda
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

                // Boton de rotacion manual en esquina superior derecha
                if (_isPlayerInitialized)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      tooltip: 'Rotar video 90°',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.65),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.rotate_right_rounded, size: 19),
                      onPressed: () {
                        setState(() {
                          _extraQuarterTurns = (_extraQuarterTurns + 1) % 4;
                        });
                      },
                    ),
                  ),

                // Boton Play / Pausa en esquina inferior derecha
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceGlass,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // 2. Indicador en Vivo de Reconocimiento de Manos
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                size: 20,
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
                    const SizedBox(height: 1),
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

        const SizedBox(height: 10),

        // 3. Timeline visual estilo WhatsApp con mapa de deteccion por frame
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inicio: ${_formatSeconds(_startFrame)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Duración: ${_formatTrimDuration()} ($totalTrimmed frames)',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Fin: ${_formatSeconds(_endFrame)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (maxFrames > 1)
                _WhatsAppTimelineTrimmer(
                  frames: widget.candidate.allFrames,
                  requiredHands: widget.requiredHands,
                  startFrame: _startFrame,
                  endFrame: _endFrame,
                  currentFrame: _currentFrameIndex,
                  isPassing: isPassing,
                  onScrubStart: _handleScrubStart,
                  onScrubUpdate: _handleScrubUpdate,
                  onScrubEnd: _handleScrubEnd,
                  onTapPlayhead: _handleTapPlayhead,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoWithOverlay() {
    if (!_isPlayerInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
        ),
      );
    }

    final val = _controller!.value;
    final rawSize = val.size;
    final rawRatio = (rawSize.width > 0 && rawSize.height > 0)
        ? (rawSize.width / rawSize.height)
        : 1.0;
    final totalTurns = ((val.rotationCorrection ~/ 90) + _extraQuarterTurns) % 4;
    final effectiveAspectRatio = totalTurns.isOdd ? (1.0 / rawRatio) : rawRatio;

    return Center(
      child: AspectRatio(
        aspectRatio: effectiveAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final pose = _getCurrentPose(size);
            return Stack(
              fit: StackFit.expand,
              children: [
                RotatedBox(
                  quarterTurns: _extraQuarterTurns,
                  child: VideoPlayer(_controller!),
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WhatsAppTimelineTrimmer extends StatefulWidget {
  final List<SignFrameLandmarks> frames;
  final int requiredHands;
  final int startFrame;
  final int endFrame;
  final int currentFrame;
  final bool isPassing;
  final ValueChanged<_TrimmerDragTarget> onScrubStart;
  final void Function(
    _TrimmerDragTarget target,
    int newStart,
    int newEnd,
    int newPlayhead,
  ) onScrubUpdate;
  final ValueChanged<_TrimmerDragTarget> onScrubEnd;
  final ValueChanged<int> onTapPlayhead;

  const _WhatsAppTimelineTrimmer({
    required this.frames,
    required this.requiredHands,
    required this.startFrame,
    required this.endFrame,
    required this.currentFrame,
    required this.isPassing,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onTapPlayhead,
  });

  @override
  State<_WhatsAppTimelineTrimmer> createState() =>
      _WhatsAppTimelineTrimmerState();
}

class _WhatsAppTimelineTrimmerState extends State<_WhatsAppTimelineTrimmer> {
  static const double _handleWidth = 14.0;
  static const double _hitRadius = 24.0;

  _TrimmerDragTarget? _activeTarget;

  int get _maxIdx => math.max(0, widget.frames.length - 1);

  double _trackLeft() => _handleWidth;

  double _trackWidth(double totalWidth) =>
      math.max(1.0, totalWidth - (_handleWidth * 2));

  double _frameToX(int frame, double totalWidth) {
    if (_maxIdx <= 0) return _trackLeft();
    final t = frame.clamp(0, _maxIdx) / _maxIdx;
    return _trackLeft() + t * _trackWidth(totalWidth);
  }

  int _xToFrame(double dx, double totalWidth) {
    if (_maxIdx <= 0) return 0;
    final t = ((dx - _trackLeft()) / _trackWidth(totalWidth)).clamp(0.0, 1.0);
    return (t * _maxIdx).round().clamp(0, _maxIdx);
  }

  _TrimmerDragTarget _hitTestTarget(double dx, double totalWidth) {
    final startX = _frameToX(widget.startFrame, totalWidth);
    final endX = _frameToX(widget.endFrame, totalWidth);
    final leftCenter = startX - (_handleWidth * 0.5);
    final rightCenter = endX + (_handleWidth * 0.5);

    final distLeft = (dx - leftCenter).abs();
    final distRight = (dx - rightCenter).abs();

    if (distLeft <= _hitRadius && distRight <= _hitRadius) {
      return distLeft <= distRight
          ? _TrimmerDragTarget.start
          : _TrimmerDragTarget.end;
    }
    if (distLeft <= _hitRadius) return _TrimmerDragTarget.start;
    if (distRight <= _hitRadius) return _TrimmerDragTarget.end;
    return _TrimmerDragTarget.playhead;
  }

  void _applyDrag(double dx, double totalWidth) {
    final target = _activeTarget;
    if (target == null) return;

    final candidate = _xToFrame(dx, totalWidth);
    final minSpan = math.min(5, _maxIdx);

    int nextStart = widget.startFrame;
    int nextEnd = widget.endFrame;
    int nextPlayhead = widget.currentFrame;

    switch (target) {
      case _TrimmerDragTarget.start:
        final upper = math.max(0, nextEnd - minSpan);
        nextStart = candidate.clamp(0, upper);
        nextPlayhead = nextStart;
        break;
      case _TrimmerDragTarget.end:
        final lower = math.min(_maxIdx, nextStart + minSpan);
        nextEnd = candidate.clamp(lower, _maxIdx);
        nextPlayhead = nextEnd;
        break;
      case _TrimmerDragTarget.playhead:
        nextPlayhead = candidate.clamp(nextStart, nextEnd);
        break;
    }

    widget.onScrubUpdate(target, nextStart, nextEnd, nextPlayhead);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final target = _hitTestTarget(details.localPosition.dx, width);
              if (target == _TrimmerDragTarget.playhead) {
                widget.onTapPlayhead(_xToFrame(details.localPosition.dx, width));
              }
            },
            onHorizontalDragStart: (details) {
              final target = _hitTestTarget(details.localPosition.dx, width);
              _activeTarget = target;
              widget.onScrubStart(target);
              _applyDrag(details.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (details) {
              _applyDrag(details.localPosition.dx, width);
            },
            onHorizontalDragEnd: (_) {
              final target = _activeTarget ?? _TrimmerDragTarget.playhead;
              _activeTarget = null;
              widget.onScrubEnd(target);
            },
            onHorizontalDragCancel: () {
              final target = _activeTarget ?? _TrimmerDragTarget.playhead;
              _activeTarget = null;
              widget.onScrubEnd(target);
            },
            child: CustomPaint(
              size: Size(width, 60),
              painter: _TimelinePainter(
                frames: widget.frames,
                requiredHands: widget.requiredHands,
                startFrame: widget.startFrame,
                endFrame: widget.endFrame,
                currentFrame: widget.currentFrame,
                activeColor:
                    widget.isPassing ? AppColors.cyanAccent : Colors.amber,
                handleWidth: _handleWidth,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<SignFrameLandmarks> frames;
  final int requiredHands;
  final int startFrame;
  final int endFrame;
  final int currentFrame;
  final Color activeColor;
  final double handleWidth;

  _TimelinePainter({
    required this.frames,
    required this.requiredHands,
    required this.startFrame,
    required this.endFrame,
    required this.currentFrame,
    required this.activeColor,
    required this.handleWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalFrames = frames.length;
    final maxIdx = math.max(1, totalFrames - 1);
    final trackLeft = handleWidth;
    final trackRight = size.width - handleWidth;
    final trackWidth = math.max(1.0, trackRight - trackLeft);

    double frameToX(int f) {
      if (totalFrames <= 1) return trackLeft;
      return trackLeft + (f.clamp(0, maxIdx) / maxIdx) * trackWidth;
    }

    final trackRect = Rect.fromLTRB(trackLeft, 4, trackRight, size.height - 4);
    final trackRRect =
        RRect.fromRectAndRadius(trackRect, const Radius.circular(6));

    // Fondo del carril
    canvas.drawRRect(
      trackRRect,
      Paint()..color = const Color(0xFF0E1322),
    );

    // Barras por frame (verde/cian cuando detecta manos suficientes, gris/rojo cuando no)
    canvas.save();
    canvas.clipRRect(trackRRect);

    final int barCount = math.min(totalFrames, math.max(1, (trackWidth / 3).floor()));
    final double barStep = trackWidth / barCount;
    final double barW = math.max(1.5, barStep - 1.0);
    final validPaint = Paint()..color = AppColors.cyanAccent.withValues(alpha: 0.78);
    final missingPaint = Paint()..color = const Color(0xFF64748B).withValues(alpha: 0.45);

    for (int i = 0; i < barCount; i++) {
      final sampleIdx = ((i / math.max(1, barCount - 1)) * maxIdx)
          .round()
          .clamp(0, totalFrames - 1);
      final hasHands = frames[sampleIdx].hands.length >= requiredHands;
      final x = trackLeft + i * barStep;
      final top = hasHands ? 10.0 : 20.0;
      final bottom = hasHands ? size.height - 10.0 : size.height - 20.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barW, bottom - top),
          const Radius.circular(1.5),
        ),
        hasHands ? validPaint : missingPaint,
      );
    }

    final startX = frameToX(startFrame);
    final endX = frameToX(endFrame);

    // Sombra oscura fuera del rango recortado
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    if (startX > trackLeft) {
      canvas.drawRect(
        Rect.fromLTRB(trackLeft, 4, startX, size.height - 4),
        scrimPaint,
      );
    }
    if (endX < trackRight) {
      canvas.drawRect(
        Rect.fromLTRB(endX, 4, trackRight, size.height - 4),
        scrimPaint,
      );
    }
    canvas.restore();

    // Marco superior e inferior del recorte estilo WhatsApp
    final borderPaint = Paint()..color = activeColor;
    canvas.drawRect(
      Rect.fromLTRB(startX - handleWidth, 0, endX + handleWidth, 4),
      borderPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        startX - handleWidth,
        size.height - 4,
        endX + handleWidth,
        size.height,
      ),
      borderPaint,
    );

    // Tirador izquierdo
    final leftHandleRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(startX - handleWidth, 0, startX, size.height),
      topLeft: const Radius.circular(6),
      bottomLeft: const Radius.circular(6),
    );
    canvas.drawRRect(leftHandleRRect, borderPaint);
    _drawGrip(canvas, startX - handleWidth * 0.5, size.height);

    // Tirador derecho
    final rightHandleRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(endX, 0, endX + handleWidth, size.height),
      topRight: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas.drawRRect(rightHandleRRect, borderPaint);
    _drawGrip(canvas, endX + handleWidth * 0.5, size.height);

    // Playhead vertical blanco
    final playheadX = frameToX(currentFrame).clamp(startX, endX);
    canvas.drawLine(
      Offset(playheadX, 2),
      Offset(playheadX, size.height - 2),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.65)
        ..strokeWidth = 4.5,
    );
    canvas.drawLine(
      Offset(playheadX, 2),
      Offset(playheadX, size.height - 2),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.4,
    );
  }

  void _drawGrip(Canvas canvas, double centerX, double height) {
    final gripPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final top = height * 0.34;
    final bottom = height * 0.66;
    canvas.drawLine(Offset(centerX - 1.8, top), Offset(centerX - 1.8, bottom), gripPaint);
    canvas.drawLine(Offset(centerX + 1.8, top), Offset(centerX + 1.8, bottom), gripPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.startFrame != startFrame ||
        oldDelegate.endFrame != endFrame ||
        oldDelegate.currentFrame != currentFrame ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.frames.length != frames.length ||
        oldDelegate.requiredHands != requiredHands;
  }
}
