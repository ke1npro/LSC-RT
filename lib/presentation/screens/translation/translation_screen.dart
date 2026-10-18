import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/translation_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_result_pill.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';
import 'widgets/calibration_sheet.dart';

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Visor de Cámara con BodyPosePainter reactivo
          CameraViewport(
            controller: translationVm.cameraDataSource.controller,
            isFrontCamera: translationVm.isFrontCamera,
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

          // 3. Indicador de Calibración Activa (si está grabando)
          if (translationVm.isCalibrating)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.redError.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.redError.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Grabando "${translationVm.targetLetter}": ${translationVm.calibrationSamplesCount}/${translationVm.totalCalibrationSamples}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => translationVm.cancelCalibration(),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Pastilla Inferior de Resultado de Traducción
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: GlassResultPill(
                  prediction: translationVm.currentPrediction,
                  hasHand: translationVm.hasHand,
                  onCalibrateTap: () => CalibrationSheet.show(context, translationVm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
