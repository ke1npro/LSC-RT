import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_colors.dart';

/// Editor previo al procesamiento para recortar inicio y fin de la grabación
/// antes de enviarla a MediaPipe.
class PreProcessVideoTrimmer extends StatefulWidget {
  final String videoPath;
  final int initialStartMs;
  final int? initialEndMs;
  final void Function(int startMs, int endMs) onTrimChanged;
  final VoidCallback onProcess;
  final VoidCallback onCancel;

  const PreProcessVideoTrimmer({
    super.key,
    required this.videoPath,
    this.initialStartMs = 0,
    this.initialEndMs,
    required this.onTrimChanged,
    required this.onProcess,
    required this.onCancel,
  });

  @override
  State<PreProcessVideoTrimmer> createState() => _PreProcessVideoTrimmerState();
}

class _PreProcessVideoTrimmerState extends State<PreProcessVideoTrimmer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  int _durationMs = 1000;
  int _startMs = 0;
  int _endMs = 1000;
  int _positionMs = 0;
  int _extraQuarterTurns = 0;
  DateTime _lastLoopSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScrubSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

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
      await ctrl.setLooping(true);

      final durMs = math.max(100, ctrl.value.duration.inMilliseconds);
      final initStart = widget.initialStartMs.clamp(0, durMs - 100);
      final initEnd =
          (widget.initialEndMs ?? durMs).clamp(initStart + 100, durMs);

      ctrl.addListener(_onPlayerTick);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _controller = ctrl;
        _initialized = true;
        _durationMs = durMs;
        _startMs = initStart;
        _endMs = initEnd;
        _positionMs = initStart;
      });
      widget.onTrimChanged(initStart, initEnd);
      await ctrl.seekTo(Duration(milliseconds: initStart));
      await ctrl.play();
    } catch (_) {}
  }

  void _onPlayerTick() {
    final ctrl = _controller;
    if (!mounted || ctrl == null || !ctrl.value.isInitialized) return;
    final posMs = ctrl.value.position.inMilliseconds;
    if (posMs != _positionMs) {
      setState(() => _positionMs = posMs);
    }
    if (ctrl.value.isPlaying && posMs >= _endMs) {
      final now = DateTime.now();
      if (now.difference(_lastLoopSeekAt).inMilliseconds >= 250) {
        _lastLoopSeekAt = now;
        ctrl.seekTo(Duration(milliseconds: _startMs));
      }
    }
  }

  void _seekThrottled(int ms) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final now = DateTime.now();
    if (now.difference(_lastScrubSeekAt).inMilliseconds < 60) return;
    _lastScrubSeekAt = now;
    ctrl.seekTo(Duration(milliseconds: ms.clamp(0, _durationMs)));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    super.dispose();
  }

  String _fmtSeconds(int ms) => '${(ms / 1000.0).toStringAsFixed(1)}s';

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final trimDurationMs = math.max(0, _endMs - _startMs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        const Text(
          'Recortar grabación antes de procesar',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ajusta el inicio y el final para analizar solo la parte con señas.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          height: 310,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _initialized && ctrl != null
                ? GestureDetector(
                    onTap: () {
                      if (ctrl.value.isPlaying) {
                        ctrl.pause();
                      } else {
                        if (_positionMs < _startMs || _positionMs >= _endMs) {
                          ctrl.seekTo(Duration(milliseconds: _startMs));
                        }
                        ctrl.play();
                      }
                      setState(() {});
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: RotatedBox(
                            quarterTurns: _extraQuarterTurns,
                            child: AspectRatio(
                              aspectRatio: ctrl.value.aspectRatio > 0
                                  ? ctrl.value.aspectRatio
                                  : 9 / 16,
                              child: VideoPlayer(ctrl),
                            ),
                          ),
                        ),
                        if (!ctrl.value.isPlaying)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.6),
                            ),
                            icon: const Icon(
                              Icons.rotate_right_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            tooltip: 'Rotar video',
                            onPressed: () => setState(
                              () => _extraQuarterTurns =
                                  (_extraQuarterTurns + 1) % 4,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Recorte: ${_fmtSeconds(trimDurationMs)} / ${_fmtSeconds(_durationMs)}',
                              style: const TextStyle(
                                color: AppColors.cyanAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.cyanAccent,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (_initialized) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Inicio: ${_fmtSeconds(_startMs)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                'Fin: ${_fmtSeconds(_endMs)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          RangeSlider(
            values: RangeValues(_startMs.toDouble(), _endMs.toDouble()),
            min: 0,
            max: _durationMs.toDouble(),
            activeColor: AppColors.cyanAccent,
            inactiveColor: Colors.white24,
            onChanged: (values) {
              final nextStart = values.start.round().clamp(0, _durationMs - 100);
              final nextEnd =
                  values.end.round().clamp(nextStart + 100, _durationMs);
              final startMoved = nextStart != _startMs;
              setState(() {
                _startMs = nextStart;
                _endMs = nextEnd;
              });
              widget.onTrimChanged(nextStart, nextEnd);
              _seekThrottled(startMoved ? nextStart : nextEnd);
            },
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.redError,
                  side: const BorderSide(color: AppColors.redError),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar'),
                onPressed: widget.onCancel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyanAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text(
                  'Procesar y Traducir',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: widget.onProcess,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
