import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/body_pose.dart';
import '../../../domain/entities/sign_prediction.dart';
import '../../viewmodels/dictionary_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/step_conversation_viewmodel.dart';
import '../../viewmodels/translation_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_result_pill.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';
import 'widgets/step_conversation_view.dart';

enum _TranslationUiMode { stepByStep, live }

class TranslationScreen extends StatefulWidget {
  final bool isActiveTab;

  const TranslationScreen({super.key, this.isActiveTab = true});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  _TranslationUiMode _uiMode = _TranslationUiMode.stepByStep;
  bool _isSwitchingMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActiveTab) return;
      context.read<StepConversationViewModel>().enterMode();
    });
  }

  @override
  void didUpdateWidget(covariant TranslationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActiveTab != widget.isActiveTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTabVisibility(widget.isActiveTab);
      });
    }
  }

  Future<void> _syncTabVisibility(bool active) async {
    final stepVm = context.read<StepConversationViewModel>();
    final liveVm = context.read<TranslationViewModel>();
    if (!active) {
      await stepVm.leaveMode();
      await liveVm.pauseLiveMode();
      return;
    }
    if (_uiMode == _TranslationUiMode.stepByStep) {
      await liveVm.pauseLiveMode();
      if (!mounted || !widget.isActiveTab) return;
      await stepVm.enterMode();
    } else {
      await stepVm.leaveMode();
      if (!mounted || !widget.isActiveTab) return;
      await liveVm.initialize();
    }
  }

  Future<void> _switchMode(_TranslationUiMode nextMode) async {
    if (_uiMode == nextMode || _isSwitchingMode) return;
    setState(() {
      _isSwitchingMode = true;
      _uiMode = nextMode;
    });

    final stepVm = context.read<StepConversationViewModel>();
    final liveVm = context.read<TranslationViewModel>();

    try {
      if (nextMode == _TranslationUiMode.live) {
        await stepVm.leaveMode();
        if (!mounted) return;
        await liveVm.initialize();
      } else {
        await liveVm.pauseLiveMode();
        if (!mounted) return;
        await stepVm.enterMode();
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingMode = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryCount =
        context.select<DictionaryViewModel, int>((d) => d.allSigns.length);

    if (_uiMode == _TranslationUiMode.stepByStep) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            GlassTopBar(
              title: 'Conversación LSC',
              subtitle: dictionaryCount == 0
                  ? 'Diccionario vacío (0 señas)'
                  : 'Modo Paso a Paso offline ($dictionaryCount señas)',
              isOnline: true,
            ),
            const SizedBox(height: 8),
            _buildModeToggle(),
            const Expanded(child: StepConversationView()),
          ],
        ),
      );
    }

    final translationVm = context.read<TranslationViewModel>();
    final isInitialized =
        context.select<TranslationViewModel, bool>((vm) => vm.isInitialized);
    final isSwitching = context
        .select<TranslationViewModel, bool>((vm) => vm.isCameraSwitching);
    final isPermissionDenied = context.select<TranslationViewModel, bool>(
        (vm) => vm.isCameraPermissionDenied);
    final controller = context.select<TranslationViewModel, CameraController?>(
        (vm) => vm.cameraDataSource.controller);
    final isFrontCamera =
        context.select<TranslationViewModel, bool>((vm) => vm.isFrontCamera);
    final errorMessage = context
        .select<TranslationViewModel, String?>((vm) => vm.cameraErrorMessage);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Visor de Cámara con BodyPosePainter reactivo aislado
          RepaintBoundary(
            child: CameraViewport(
              controller: controller,
              isFrontCamera: isFrontCamera,
              isSwitching: isSwitching,
              isPermissionDenied: isPermissionDenied,
              errorMessage: errorMessage,
              onRetry: () => translationVm.retryCamera(),
              onSizeChanged: (size) => translationVm.setViewportSize(size),
              overlay: Selector<TranslationViewModel, BodyPose?>(
                selector: (_, vm) => vm.currentPose,
                builder: (context, currentPose, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: BodyPosePainter(
                        pose: currentPose,
                        showOverlay: context.select<SettingsViewModel, bool>(
                            (s) => s.showMediaPipeOverlay),
                        showFace: context.select<SettingsViewModel, bool>(
                            (s) => s.showFaceDetection),
                        isMirrored: isFrontCamera,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 2. Barra Superior Flotante Glassmorphism + Selector de Modo
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassTopBar(
                  title: 'LSC RT',
                  subtitle: dictionaryCount == 0
                      ? 'Diccionario vacío (0 señas)'
                      : 'Traducción desde tu Diccionario ($dictionaryCount)',
                  isOnline: isInitialized,
                  onSwitchCamera: () => translationVm.switchCamera(),
                ),
                const SizedBox(height: 8),
                _buildModeToggle(),
              ],
            ),
          ),

          // 3. Área Inferior: Historial de 5 palabras + Pastilla de Resultado
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Selector2<TranslationViewModel, DictionaryViewModel,
                (SignPrediction?, bool, List<String>, int)>(
              selector: (_, vm, dict) => (
                vm.currentPrediction,
                vm.hasHand,
                vm.recentWords,
                dict.allSigns.length,
              ),
              builder: (context, data, _) {
                final prediction = data.$1;
                final hasHand = data.$2;
                final recentWords = data.$3;
                final dictCount = data.$4;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (recentWords.isNotEmpty) ...[
                            _buildRecentWordsRibbon(recentWords),
                            const SizedBox(height: 10),
                          ],
                          GlassResultPill(
                            prediction: prediction,
                            hasHand: hasHand,
                            isCalibrationAvailable: false,
                            isDictionaryEmpty: dictCount == 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xF2121727),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            _buildModeSegment(
              label: 'Paso a Paso',
              icon: Icons.chat_bubble_outline_rounded,
              selected: _uiMode == _TranslationUiMode.stepByStep,
              onTap: () => _switchMode(_TranslationUiMode.stepByStep),
            ),
            _buildModeSegment(
              label: 'En Vivo',
              icon: Icons.sensors_rounded,
              selected: _uiMode == _TranslationUiMode.live,
              onTap: () => _switchMode(_TranslationUiMode.live),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.cyanAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.black : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentWordsRibbon(List<String> recentWords) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2121727),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
                children: List.generate(recentWords.length, (idx) {
                  final word = recentWords[idx];
                  final isLast = idx == recentWords.length - 1;
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
                onPressed: () =>
                    context.read<TranslationViewModel>().clearRecentWords(),
              ),
            ],
          ),
        );
  }
}
