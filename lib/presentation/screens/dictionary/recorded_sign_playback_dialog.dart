import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/body_pose.dart';
import '../../../domain/entities/recorded_sign.dart';
import '../../../domain/usecases/resolve_body_pose_usecase.dart';
import '../../widgets/painters/body_pose_painter.dart';

class RecordedSignPlaybackDialog extends StatefulWidget {
  final RecordedSign sign;

  const RecordedSignPlaybackDialog({super.key, required this.sign});

  static Future<void> show(BuildContext context, RecordedSign sign) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => RecordedSignPlaybackDialog(sign: sign),
    );
  }

  @override
  State<RecordedSignPlaybackDialog> createState() => _RecordedSignPlaybackDialogState();
}

class _RecordedSignPlaybackDialogState extends State<RecordedSignPlaybackDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final ResolveBodyPoseUseCase _resolveBodyPose = ResolveBodyPoseUseCase();
  double _playbackSpeed = 1.0;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    final frameCount = widget.sign.frameCount;
    final durationSeconds = (frameCount > 0) ? (frameCount / widget.sign.fps) : 1.0;

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (durationSeconds * 1000).toInt()),
    )..addListener(() {
        setState(() {});
      });

    _animController.repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  int get _currentFrameIndex {
    if (widget.sign.frames.isEmpty) return 0;
    final idx = (_animController.value * (widget.sign.frames.length - 1)).round();
    return idx.clamp(0, widget.sign.frames.length - 1);
  }

  BodyPose? _getCurrentPose(Size size) {
    if (widget.sign.frames.isEmpty) return null;
    final frame = widget.sign.frames[_currentFrameIndex];

    return _resolveBodyPose.execute(
      hands: frame.hands,
      faces: const [],
      logicalWidth: size.width,
      logicalHeight: size.height,
    );
  }

  void _togglePlayPause() {
    setState(() {
      if (_animController.isAnimating) {
        _animController.stop();
        _isPlaying = false;
      } else {
        _animController.repeat();
        _isPlaying = true;
      }
    });
  }

  void _cycleSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 0.5;
      } else if (_playbackSpeed == 0.5) {
        _playbackSpeed = 1.5;
      } else {
        _playbackSpeed = 1.0;
      }
      final baseMs = (widget.sign.frameCount / widget.sign.fps) * 1000;
      _animController.duration = Duration(milliseconds: (baseMs / _playbackSpeed).toInt());
      if (_isPlaying) {
        _animController.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.sign;
    final pct = (sign.detectionRate * 100).toStringAsFixed(1);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF2121727),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sign.word,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceGlass,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sign.category,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.cyanAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sign.isBimanual ? '2 Manos' : '1 Mano',
                                style: const TextStyle(
                                  color: AppColors.cyanAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x3300C853),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pct% detección',
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(color: AppColors.glassBorder, height: 1),

            // Visor de landmarks con Two-Bone IK
            Container(
              height: 320,
              width: double.infinity,
              color: const Color(0xFF0A0E1A),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  final pose = _getCurrentPose(size);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (pose != null)
                        CustomPaint(
                          size: Size.infinite,
                          painter: BodyPosePainter(
                            pose: pose,
                            showOverlay: true,
                            showFace: false,
                            isMirrored: false,
                          ),
                        )
                      else
                        const Center(
                          child: Text(
                            'Sin datos de esqueleto',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),

                      // Contador de frames
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Cuadro $_currentFrameIndex / ${sign.frameCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Controles de Reproducción
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: AppColors.cyanAccent,
                      activeTrackColor: AppColors.cyanAccent,
                      inactiveTrackColor: AppColors.glassBorder,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _animController.value.clamp(0.0, 1.0),
                      onChanged: (val) {
                        _animController.value = val;
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                        onPressed: _cycleSpeed,
                        icon: const Icon(Icons.speed_rounded, size: 18),
                        label: Text('${_playbackSpeed}x'),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                        icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: _togglePlayPause,
                      ),
                      Text(
                        '~${(sign.frameCount / sign.fps).toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
