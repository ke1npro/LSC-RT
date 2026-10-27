import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/translation_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_result_pill.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<TranslationViewModel>();
      if (!vm.isInitialized) {
        vm.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final translationVm = context.watch<TranslationViewModel>();
    final settingsVm = context.watch<SettingsViewModel>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Visor de Cámara con BodyPosePainter reactivo
          CameraViewport(
            controller: translationVm.cameraDataSource.controller,
            isFrontCamera: translationVm.isFrontCamera,
            isSwitching: translationVm.isCameraSwitching,
            isPermissionDenied: translationVm.isCameraPermissionDenied,
            errorMessage: translationVm.cameraErrorMessage,
            onRetry: () => translationVm.retryCamera(),
            onSizeChanged: (size) => translationVm.setViewportSize(size),
            overlay: CustomPaint(
              size: Size.infinite,
              painter: BodyPosePainter(
                pose: translationVm.currentPose,
                showOverlay: settingsVm.showMediaPipeOverlay,
                showFace: settingsVm.showFaceDetection,
                isMirrored: translationVm.isFrontCamera,
              ),
            ),
          ),

          // 2. Barra Superior Flotante Glassmorphism
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'LSC RT',
              subtitle: 'Traducción en Tiempo Real',
              isOnline: translationVm.isInitialized,
              onSwitchCamera: () => translationVm.switchCamera(),
            ),
          ),

          // 3. Área Inferior: Historial de 5 palabras + Pastilla de Resultado
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Historial de las últimas 5 palabras reconocidas
                      if (translationVm.recentWords.isNotEmpty) ...[
                        _buildRecentWordsRibbon(translationVm),
                        const SizedBox(height: 10),
                      ],

                      // Pastilla principal de resultado
                      GlassResultPill(
                        prediction: translationVm.currentPrediction,
                        hasHand: translationVm.hasHand,
                        isCalibrationAvailable: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWordsRibbon(TranslationViewModel vm) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: AppColors.cyanAccent, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Últimas:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(vm.recentWords.length, (idx) {
                      final word = vm.recentWords[idx];
                      final isLast = idx == vm.recentWords.length - 1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLast
                                ? AppColors.cyanAccent.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isLast
                                  ? AppColors.cyanAccent
                                  : AppColors.glassBorder,
                            ),
                          ),
                          child: Text(
                            word,
                            style: TextStyle(
                              color: isLast
                                  ? AppColors.cyanAccent
                                  : AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight:
                                  isLast ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Limpiar historial',
                onPressed: () => vm.clearRecentWords(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
