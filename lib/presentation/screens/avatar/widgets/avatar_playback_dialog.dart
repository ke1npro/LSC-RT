import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/avatar_theme.dart';
import '../../../viewmodels/avatar_viewmodel.dart';
import '../../../widgets/avatar/avatar_pose_painter.dart';

class AvatarPlaybackDialog extends StatelessWidget {
  final AvatarViewModel viewModel;

  const AvatarPlaybackDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, AvatarViewModel vm) {
    vm.play();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AvatarPlaybackDialog(viewModel: vm),
    ).then((_) => vm.stop());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final currentWord = viewModel.currentWordDisplayName;
        final progress = viewModel.totalFrames > 0
            ? viewModel.currentFrameIndex / viewModel.totalFrames
            : 0.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
                decoration: BoxDecoration(
                  color: AppColors.surfaceGlass,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 1. Barra superior del modal
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.cyanAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.accessibility_new_rounded,
                              color: AppColors.cyanAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Interpretación LSC',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Avatar Cinemático Digital',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
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

                    const Divider(height: 1, color: AppColors.glassBorder),

                    // 2. Frase con la palabra activa destacada
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.black.withValues(alpha: 0.2),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: List.generate(viewModel.sentenceSequence.length, (idx) {
                          final isCurrent = idx == viewModel.currentWordIndex;
                          final sign = viewModel.sentenceSequence[idx];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.cyanAccent.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.cyanAccent
                                    : AppColors.glassBorder,
                                width: isCurrent ? 1.5 : 1.0,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: AppColors.cyanAccent.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              sign.displayName,
                              style: TextStyle(
                                color: isCurrent
                                    ? AppColors.cyanAccent
                                    : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // 3. Canvas del Avatar animado
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF151D33), Color(0xFF0B1020)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.cyanAccent.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Avatar cinemático
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: AvatarPosePainter(
                                    frame: viewModel.currentFrame,
                                    theme: viewModel.theme,
                                    rightHandTrail: viewModel.rightHandTrail,
                                    leftHandTrail: viewModel.leftHandTrail,
                                  ),
                                ),

                                // Indicador de palabra actual en la esquina inferior
                                if (currentWord.isNotEmpty)
                                  Positioned(
                                    bottom: 12,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.glassBorder,
                                        ),
                                      ),
                                      child: Text(
                                        'Seña: $currentWord',
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
                          ),
                        ),
                      ),
                    ),

                    // 4. Barra de progreso cinemático
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.cyanAccent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 5. Controles de Reproducción y Estilo
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          // Botón Replay
                          IconButton(
                            icon: const Icon(Icons.replay_rounded,
                                color: AppColors.textSecondary),
                            tooltip: 'Reiniciar',
                            onPressed: () => viewModel.replay(),
                          ),

                          // Botón Play / Pause principal
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppColors.cyanAccent, Color(0xFF0077FE)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cyanAccent.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                viewModel.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 28,
                              ),
                              onPressed: () {
                                if (viewModel.isPlaying) {
                                  viewModel.pause();
                                } else {
                                  viewModel.play();
                                }
                              },
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Selector de velocidad
                          PopupMenuButton<double>(
                            tooltip: 'Velocidad de reproducción',
                            initialValue: viewModel.playbackSpeed,
                            onSelected: (speed) => viewModel.setPlaybackSpeed(speed),
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 0.5, child: Text('0.5x (Lento)')),
                              const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                              const PopupMenuItem(value: 1.5, child: Text('1.5x (Rápido)')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Text(
                                '${viewModel.playbackSpeed}x',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Selector de Estilo / Tema (Customización Modular)
                          PopupMenuButton<AvatarTheme>(
                            tooltip: 'Estilo Visual del Avatar',
                            onSelected: (t) => viewModel.setTheme(t),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: AvatarTheme.character(),
                                child: const Text('Personaje'),
                              ),
                              PopupMenuItem(
                                value: AvatarTheme.highContrast(),
                                child: const Text('Alto Contraste Didáctico'),
                              ),
                              PopupMenuItem(
                                value: AvatarTheme.emerald(),
                                child: const Text('Esmeralda'),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.palette_outlined,
                                      color: AppColors.cyanAccent, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Estilo',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ),
        );
      },
    );
  }
}
