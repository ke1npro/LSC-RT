import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/teaching_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';
import '../../widgets/painters/guide_pose_painter.dart';

class TeachingScreen extends StatefulWidget {
  const TeachingScreen({super.key});

  @override
  State<TeachingScreen> createState() => _TeachingScreenState();
}

class _TeachingScreenState extends State<TeachingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addListener(() {
        if (mounted) {
          context.read<TeachingViewModel>().updateAnimation(_animController.value);
        }
      });
    _animController.repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<TeachingViewModel>();
      if (!vm.isInitialized) {
        vm.initialize();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teachingVm = context.watch<TeachingViewModel>();
    final settingsVm = context.watch<SettingsViewModel>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final score = teachingVm.matchScore;
    final scorePercent = (score * 100).toInt();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Visor de Cámara con GuidePose y BodyPose (opcional)
          CameraViewport(
            controller: teachingVm.cameraDataSource.controller,
            isFrontCamera: teachingVm.isFrontCamera,
            isSwitching: teachingVm.isCameraSwitching,
            isPermissionDenied: teachingVm.isCameraPermissionDenied,
            errorMessage: teachingVm.cameraErrorMessage,
            onRetry: () => teachingVm.retryCamera(),
            onSizeChanged: (size) => teachingVm.setViewportSize(size),
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                // Guía del tutor (Wave)
                CustomPaint(
                  size: Size.infinite,
                  painter: GuidePosePainter(
                    guidePose: teachingVm.guidePose,
                    matchScore: score,
                  ),
                ),

                // Esqueleto real del usuario (condicionado a settings)
                if (settingsVm.showTeachingMediaPipeOverlay)
                  CustomPaint(
                    size: Size.infinite,
                    painter: BodyPosePainter(
                      pose: teachingVm.userPose,
                      showOverlay: true,
                      showFace: settingsVm.showFaceDetection,
                      isMirrored: teachingVm.isFrontCamera,
                    ),
                  ),
              ],
            ),
          ),

          // 2. Barra Superior Flotante Glassmorphism
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Tutor en Vivo',
              subtitle: 'Práctica de Saludo LSC (Wave)',
              isOnline: teachingVm.isInitialized,
              onSwitchCamera: () => teachingVm.switchCamera(),
            ),
          ),

          // 3. Pastilla Inferior de Coincidencia Postural
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceGlass,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            // Medidor circular de puntaje
                            Container(
                              width: 52,
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (score > 0.75
                                        ? AppColors.mintGreen
                                        : AppColors.guideViolet)
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: (score > 0.75
                                          ? AppColors.mintGreen
                                          : AppColors.guideViolet)
                                      .withValues(alpha: 0.6),
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '$scorePercent%',
                                style: TextStyle(
                                  color: score > 0.75
                                      ? AppColors.mintGreen
                                      : AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Instrucciones y feedback
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    score > 0.75
                                        ? '¡Excelente postura!'
                                        : (teachingVm.hasUserHand
                                            ? 'Alineando con el tutor...'
                                            : 'Levanta tu mano para practicar'),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: score.clamp(0.0, 1.0),
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.1),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        score > 0.75
                                            ? AppColors.mintGreen
                                            : AppColors.guideViolet,
                                      ),
                                      minHeight: 5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Imita el movimiento de saludo del modelo guía',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
