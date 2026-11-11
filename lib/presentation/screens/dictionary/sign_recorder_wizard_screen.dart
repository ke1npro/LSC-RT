import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/sign_recorder_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import 'widgets/video_trimmer_view.dart';

class SignRecorderWizardScreen extends StatefulWidget {
  const SignRecorderWizardScreen({super.key});

  @override
  State<SignRecorderWizardScreen> createState() => _SignRecorderWizardScreenState();
}

class _SignRecorderWizardScreenState extends State<SignRecorderWizardScreen> {
  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController(text: 'General');

  static const List<String> _suggestedCategories = [
    'General',
    'Saludos',
    'Cortesía',
    'Familia',
    'Universidad',
    'Comida',
    'Tiempo',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignRecorderViewModel>().initSetup();
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _handleCancel(SignRecorderViewModel vm) async {
    final shouldExit = await _confirmExit();
    if (!shouldExit || !mounted) return;
    await vm.cancelAndCleanup();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _handleSave(SignRecorderViewModel vm) async {
    final savedSign = await vm.finishAndSave();
    if (savedSign == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Seña "${savedSign.word}" guardada exitosamente'),
        backgroundColor: const Color(0xFF00C853),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SignRecorderViewModel>();

    return PopScope(
      canPop: vm.step == WizardStep.setup,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleCancel(vm);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: const Color(0xF2121727),
          title: Text(
            _getAppBarTitle(vm.step),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () {
              if (vm.step == WizardStep.setup) {
                Navigator.of(context).pop();
              } else {
                _handleCancel(vm);
              }
            },
          ),
          actions: [
            if (vm.step != WizardStep.setup && vm.step != WizardStep.processing)
              TextButton(
                onPressed: () => _handleCancel(vm),
                child: const Text('Cancelar', style: TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
        body: SafeArea(
          child: _buildBody(context, vm),
        ),
      ),
    );
  }

  String _getAppBarTitle(WizardStep step) {
    switch (step) {
      case WizardStep.setup:
        return 'Nueva Seña LSC';
      case WizardStep.cameraPreview:
        return 'Preparar Grabación';
      case WizardStep.countdown:
        return 'Grabación en...';
      case WizardStep.recording:
        return 'Grabando Seña';
      case WizardStep.processing:
        return 'Procesando Video';
      case WizardStep.trimReview:
        return 'Revisar y Recortar';
      case WizardStep.takesSummary:
        return 'Resumen de Tomas';
    }
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        title: const Text('¿Descartar grabación?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se eliminarán los videos y datos temporales de esta sesión.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar grabando', style: TextStyle(color: AppColors.cyanAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildBody(BuildContext context, SignRecorderViewModel vm) {
    switch (vm.step) {
      case WizardStep.setup:
        return _buildSetupStep(context, vm);
      case WizardStep.cameraPreview:
      case WizardStep.countdown:
      case WizardStep.recording:
        return _buildCameraStep(context, vm);
      case WizardStep.processing:
        return _buildProcessingStep(context, vm);
      case WizardStep.trimReview:
        return _buildTrimReviewStep(context, vm);
      case WizardStep.takesSummary:
        return _buildTakesSummaryStep(context, vm);
    }
  }

  // PASO 1: METADATOS
  Widget _buildSetupStep(BuildContext context, SignRecorderViewModel vm) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: const Row(
            children: [
              Icon(Icons.video_call_rounded, color: AppColors.cyanAccent, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Graba una nueva seña desde cero. Podrás tomar de 1 a 5 muestras y la app seleccionará automáticamente la de mejor reconocimiento.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Palabra
        const Text(
          'Palabra o Significado',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _wordController,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Ej. BUENOS DIAS, GRACIAS, AGUA...',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceGlass,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.cyanAccent),
            ),
          ),
          onChanged: (val) => vm.updateMetadata(word: val),
        ),

        const SizedBox(height: 20),

        // Manos requeridas
        const Text(
          'Tipo de Seña (Manos requeridas)',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Center(
                  child: Text(
                    '1 Mano (Unimanual)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                selected: vm.requiredHands == 1,
                selectedColor: AppColors.cyanAccent,
                labelStyle: TextStyle(
                  color: vm.requiredHands == 1 ? Colors.black : Colors.white,
                ),
                onSelected: (_) => vm.updateMetadata(requiredHands: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceChip(
                label: const Center(
                  child: Text(
                    '2 Manos (Bimanual)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                selected: vm.requiredHands == 2,
                selectedColor: AppColors.cyanAccent,
                labelStyle: TextStyle(
                  color: vm.requiredHands == 2 ? Colors.black : Colors.white,
                ),
                onSelected: (_) => vm.updateMetadata(requiredHands: 2),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Categoría
        const Text(
          'Categoría',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestedCategories.map((cat) {
            final isSelected = vm.category.toLowerCase() == cat.toLowerCase();
            return ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              selectedColor: AppColors.cyanAccent,
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
              ),
              onSelected: (_) {
                _categoryController.text = cat;
                vm.updateMetadata(category: cat);
              },
            );
          }).toList(),
        ),

        if (vm.errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Text(
              vm.errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],

        const SizedBox(height: 32),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyanAccent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => vm.proceedToCamera(),
          icon: const Icon(Icons.videocam_rounded),
          label: const Text(
            'Continuar a la Cámara',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // PASO 2: CÁMARA (PREVIEW, COUNTDOWN, RECORDING)
  Widget _buildCameraStep(BuildContext context, SignRecorderViewModel vm) {
    final cameraController = vm.cameraDataSource.controller;
    final isFrontCamera = vm.cameraDataSource.selectedCameraIndex == 1 ||
        (vm.cameraDataSource.currentCamera != null &&
            vm.cameraDataSource.currentCamera!.lensDirection.name == 'front');

    final takeNum = vm.takes.length + 1;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Visor de Cámara sin stream YUV activo (100% FPS para MP4)
        CameraViewport(
          controller: cameraController,
          isFrontCamera: isFrontCamera,
          isSwitching: vm.cameraDataSource.isSwitching,
          isPermissionDenied: vm.cameraDataSource.isPermissionDenied,
          errorMessage: vm.cameraDataSource.errorMessage,
          onRetry: () => vm.cameraDataSource.initializeCamera(),
        ),

        // Barra informativa superior
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Toma $takeNum de 5: "${vm.word}"',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyanAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vm.requiredHands == 2 ? '2 Manos' : '1 Mano',
                    style: const TextStyle(
                      color: AppColors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Overlay de Cuenta Regresiva (3 - 2 - 1)
        if (vm.step == WizardStep.countdown)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: Center(
              child: Text(
                '${vm.countdownSeconds}',
                style: const TextStyle(
                  color: AppColors.cyanAccent,
                  fontSize: 110,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),

        // Controles Inferiores de Grabación
        Positioned(
          bottom: 24,
          left: 20,
          right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (vm.step == WizardStep.recording) ...[
                // Barra de tiempo restante (máx 6s)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (vm.recordingSeconds / SignRecorderViewModel.maxRecordingSeconds)
                        .clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${vm.recordingSeconds.toStringAsFixed(1)}s / ${SignRecorderViewModel.maxRecordingSeconds.toInt()}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                FloatingActionButton.extended(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Detener Grabación'),
                  onPressed: () => vm.stopRecording(),
                ),
              ] else if (vm.step == WizardStep.cameraPreview) ...[
                const Text(
                  'Ubica tus manos frente a la cámara y presiona Grabar',
                  style: TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => vm.startCountdown(),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.redAccent,
                    ),
                    child: const Center(
                      child: Icon(Icons.fiber_manual_record, color: Colors.white, size: 36),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // PASO 3: PROCESAMIENTO OFFLINE
  Widget _buildProcessingStep(BuildContext context, SignRecorderViewModel vm) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xF2121727),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
              strokeWidth: 4,
            ),
            const SizedBox(height: 24),
            const Text(
              'Procesando video offline',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MediaPipe Tasks Vision está extrayendo los landmarks cuadro a cuadro...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (vm.processingPercent / 100.0).clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceGlass,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${vm.processedFrames} / ${vm.totalProcessingFrames} frames (${vm.processingPercent.toInt()}%)',
              style: const TextStyle(
                color: AppColors.cyanAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PASO 4: REVISAR Y RECORTAR CON OVERLAY DE MEDIAPIPE
  Widget _buildTrimReviewStep(BuildContext context, SignRecorderViewModel vm) {
    final candidate = vm.activeTake;
    if (candidate == null) {
      return const Center(child: Text('No hay toma para revisar'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Toma ${candidate.takeNumber} de ${vm.takes.length}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (vm.takes.length > 1)
                TextButton.icon(
                  onPressed: () => vm.viewTakesSummary(),
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Ver todas las tomas'),
                ),
            ],
          ),
        ),

        Expanded(
          child: VideoTrimmerView(
            candidate: candidate,
            requiredHands: vm.requiredHands,
            onTrimChanged: (start, end) {
              vm.updateActiveTakeTrim(start, end);
            },
          ),
        ),

        // Acciones inferiores
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              if (vm.takes.length < 5)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cyanAccent,
                      side: const BorderSide(color: AppColors.cyanAccent),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => vm.recordAnotherTake(),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                    label: Text('Grabar toma ${vm.takes.length + 1}/5'),
                  ),
                ),
              if (vm.takes.length < 5) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => vm.viewTakesSummary(),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(vm.takes.length == 1 ? 'Continuar' : 'Evaluar Muestras'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // PASO 5: RESUMEN Y SELECCIÓN DE MEJOR MUESTRA (1 A 5 TOMAS)
  Widget _buildTakesSummaryStep(BuildContext context, SignRecorderViewModel vm) {
    final eval = vm.bestEvaluation;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Evaluación de Tomas Grabadas',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'La app selecciona automáticamente la muestra con mayor % de reconocimiento en el rango recortado.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),

        ...vm.takes.asMap().entries.map((entry) {
          final idx = entry.key;
          final take = entry.value;
          final isWinner = eval?.winner.takeNumber == take.takeNumber;
          final rate = take.detectionRate(vm.requiredHands);
          final pct = (rate * 100).toStringAsFixed(1);
          final valid = take.validFramesCount(vm.requiredHands);
          final total = take.trimmedFramesCount;
          final isPassing = rate >= 0.70;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isWinner
                  ? AppColors.cyanAccent.withValues(alpha: 0.12)
                  : AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isWinner ? AppColors.cyanAccent : AppColors.glassBorder,
                width: isWinner ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isWinner ? AppColors.cyanAccent : AppColors.surfaceGlass,
                  foregroundColor: isWinner ? Colors.black : Colors.white,
                  child: Text('${take.takeNumber}'),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Toma ${take.takeNumber}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isWinner) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.cyanAccent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'MEJOR MUESTRA',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$valid / $total frames válidos ($pct%)',
                        style: TextStyle(
                          color: isPassing ? const Color(0xFF00E676) : Colors.amber,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => vm.selectTakeForReview(idx),
                  child: const Text('Recortar'),
                ),
              ],
            ),
          );
        }),

        if (eval != null && !eval.isAcceptable) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ninguna toma alcanza el 70% mínimo de detección de manos. Te sugerimos grabar una nueva toma con mejor iluminación.',
                    style: TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        if (vm.takes.length < 5)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyanAccent,
              side: const BorderSide(color: AppColors.cyanAccent),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => vm.recordAnotherTake(),
            icon: const Icon(Icons.add_a_photo_rounded),
            label: Text('Grabar otra toma (${vm.takes.length}/5)'),
          ),

        const SizedBox(height: 12),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: (eval?.isAcceptable ?? false)
                ? AppColors.cyanAccent
                : Colors.grey.shade700,
            foregroundColor: (eval?.isAcceptable ?? false) ? Colors.black : Colors.white60,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: ((eval?.isAcceptable ?? false) && !vm.isBusy)
              ? () => _handleSave(vm)
              : null,
          icon: vm.isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.save_rounded),
          label: Text(
            vm.isBusy ? 'Guardando...' : 'Guardar Seña en Diccionario',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
