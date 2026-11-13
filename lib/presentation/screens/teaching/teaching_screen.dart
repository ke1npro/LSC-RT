import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/recorded_sign.dart';
import '../../../domain/usecases/evaluate_recorded_sign_practice_usecase.dart';
import '../../viewmodels/teaching_viewmodel.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';
import 'widgets/practice_attempt_player.dart';

class TeachingScreen extends StatefulWidget {
  const TeachingScreen({super.key});

  @override
  State<TeachingScreen> createState() => _TeachingScreenState();
}

class _TeachingScreenState extends State<TeachingScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<TeachingViewModel>();
      if (!vm.isInitialized) {
        vm.initialize();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeachingViewModel>();

    switch (vm.mode) {
      case TeachingMode.catalog:
        return _buildCatalogView(context, vm);
      case TeachingMode.demonstration:
        return _buildDemonstrationView(context, vm);
      case TeachingMode.practiceReady:
      case TeachingMode.practiceCountdown:
      case TeachingMode.practiceRecording:
        return _buildPracticeCameraView(context, vm);
      case TeachingMode.practiceProcessing:
        return _buildProcessingView(context, vm);
      case TeachingMode.practiceResult:
        return _buildResultView(context, vm);
    }
  }

  // VISTA 1: CATÁLOGO DE SEÑAS DEL DICCIONARIO
  Widget _buildCatalogView(BuildContext context, TeachingViewModel vm) {
    final signs = vm.filteredSigns;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.cyanAccent,
              onRefresh: () => vm.refreshCatalog(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 80, 20, bottomPadding + 20),
                children: [
                  // Encabezado pedagógico
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGlass,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.school_rounded,
                            color: AppColors.cyanAccent, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Aprende y Practica LSC',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Estudia el movimiento de cada seña y graba una práctica de 6s para recibir tu porcentaje de confianza.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Buscador
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => vm.setSearchQuery(val),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar seña para practicar...',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textSecondary, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    color: AppColors.textSecondary, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  vm.setSearchQuery('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Filtro por categoría
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: vm.categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = vm.categories[index];
                        final isSelected = vm.selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(
                            cat,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.cyanAccent,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.cyanAccent
                                : AppColors.glassBorder,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (_) => vm.setSelectedCategory(cat),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  if (vm.dictionaryRepository.allSigns.isEmpty)
                    _buildEmptyDictionaryBanner()
                  else if (signs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No hay señas que coincidan con tu búsqueda.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...signs.map((sign) => _buildSignCatalogCard(vm, sign)),
                ],
              ),
            ),
          ),

          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Enseñanza LSC',
              subtitle: 'Práctica Guiada y Evaluación Offline',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDictionaryBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.menu_book_rounded, color: AppColors.cyanAccent, size: 40),
          SizedBox(height: 12),
          Text(
            'Aún no hay señas en tu diccionario',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Graba al menos una seña en la pestaña Diccionario para poder estudiarla y practicarla aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignCatalogCard(TeachingViewModel vm, RecordedSign sign) {
    final durationSec = (sign.frameCount / (sign.fps > 0 ? sign.fps : 30.0))
        .toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => vm.selectSign(sign),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.cyanAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.cyanAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sign.word,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            sign.category,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sign.isBimanual ? '2 Manos' : '1 Mano',
                            style: const TextStyle(
                              color: AppColors.cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${durationSec}s',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // VISTA 2: DEMOSTRACIÓN DEL ESQUELETO GUÍA
  Widget _buildDemonstrationView(BuildContext context, TeachingViewModel vm) {
    final sign = vm.selectedSign;
    if (sign == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xF2121727),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => vm.backToCatalog(),
        ),
        title: Text(
          'Estudiar: ${sign.word}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => vm.cycleDemoSpeed(),
            icon: const Icon(Icons.speed_rounded, color: AppColors.cyanAccent, size: 18),
            label: Text(
              '${vm.demoSpeed}x',
              style: const TextStyle(color: AppColors.cyanAccent),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    final pose = vm.buildDemoPose(size);

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
                              'Sin fotogramas de referencia',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        Positioned(
                          top: 14,
                          left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              'Cuadro ${vm.demoFrameIndex + 1} / ${sign.frameCount}  (${sign.isBimanual ? "2 Manos" : "1 Mano"})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  const Text(
                    'Observa la postura y trayectoria de la seña guía. Cuando estés listo, graba tu práctica de hasta 6 segundos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyanAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => vm.startPracticeSetup(),
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text(
                      'Practicar con Grabación (6s)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // VISTA 3: CÁMARA DE PRÁCTICA (PREVIEW, COUNTDOWN 3-2-1, RECORDING 6s)
  Widget _buildPracticeCameraView(BuildContext context, TeachingViewModel vm) {
    final sign = vm.selectedSign;
    final controller = vm.cameraDataSource.controller;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xF2121727),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: vm.mode == TeachingMode.practiceRecording
              ? null
              : () => vm.backToDemonstration(),
        ),
        title: Text(
          'Practicar: ${sign?.word ?? ""}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (vm.mode == TeachingMode.practiceReady)
            IconButton(
              icon: const Icon(Icons.cameraswitch_rounded,
                  color: AppColors.cyanAccent),
              onPressed: () => vm.switchCamera(),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraViewport(
              controller: controller,
              isFrontCamera: vm.isFrontCamera,
              isSwitching: vm.isCameraSwitching,
              isPermissionDenied: vm.isCameraPermissionDenied,
              errorMessage: vm.cameraErrorMessage,
              onRetry: () => vm.retryCamera(),
            ),

            // Pill superior de referencia
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Objetivo: ${sign?.word ?? ""}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.cyanAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (sign?.isBimanual ?? false) ? '2 Manos' : '1 Mano',
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

            // Overlay de cuenta regresiva 3 - 2 - 1
            if (vm.mode == TeachingMode.practiceCountdown)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
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

            // Controles inferiores
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.errorMessage != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        vm.errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                  if (vm.mode == TeachingMode.practiceRecording) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (vm.recordingSeconds /
                                TeachingViewModel.maxPracticeSeconds)
                            .clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.redAccent),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${vm.recordingSeconds.toStringAsFixed(1)}s / ${TeachingViewModel.maxPracticeSeconds.toInt()}s',
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
                      label: const Text('Detener y Evaluar'),
                      onPressed: () => vm.stopPracticeRecording(),
                    ),
                  ] else if (vm.mode == TeachingMode.practiceReady) ...[
                    const Text(
                      'Presiona grabar y realiza la seña (hasta 6 segundos)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => vm.startPracticeCountdown(),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.redAccent,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.fiber_manual_record,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // VISTA 4: PROCESAMIENTO OFFLINE
  Widget _buildProcessingView(BuildContext context, TeachingViewModel vm) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
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
                'Evaluando tu práctica offline',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Analizando postura y trayectoria cuadro a cuadro con MediaPipe...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (vm.processingPercent / 100.0).clamp(0.0, 1.0),
                  backgroundColor: AppColors.surfaceGlass,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
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
      ),
    );
  }

  // VISTA 5: RESULTADO Y % DE CONFIANZA
  Widget _buildResultView(BuildContext context, TeachingViewModel vm) {
    final result = vm.evaluationResult;
    final sign = vm.selectedSign;
    if (result == null || sign == null) return const SizedBox.shrink();

    final Color scoreColor;
    final String verdictLabel;
    final IconData verdictIcon;

    switch (result.verdict) {
      case PracticeVerdict.mastered:
        scoreColor = const Color(0xFF00E676);
        verdictLabel = 'Seña Lograda';
        verdictIcon = Icons.verified_rounded;
        break;
      case PracticeVerdict.almostThere:
        scoreColor = Colors.amber;
        verdictLabel = 'Casi Listo';
        verdictIcon = Icons.trending_up_rounded;
        break;
      case PracticeVerdict.needsPractice:
        scoreColor = Colors.orangeAccent;
        verdictLabel = 'Sigue Practicando';
        verdictIcon = Icons.replay_rounded;
        break;
      case PracticeVerdict.insufficientHands:
        scoreColor = Colors.redAccent;
        verdictLabel = 'Manos No Detectadas';
        verdictIcon = Icons.pan_tool_alt_rounded;
        break;
    }

    final shapePct = (result.shapeAndMotionScore * 100).round();
    final detectPct = (result.handDetectionRate * 100).round();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xF2121727),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => vm.backToCatalog(),
        ),
        title: Text(
          'Resultado: ${sign.word}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Tarjeta principal de % de Confianza
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: scoreColor.withValues(alpha: 0.6), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(verdictIcon, color: scoreColor, size: 26),
                      const SizedBox(width: 8),
                      Text(
                        verdictLabel,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${result.confidencePercent}%',
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Confianza de Ejecución',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    result.feedbackMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Desglose de métricas
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Forma y Movimiento',
                    value: '$shapePct%',
                    icon: Icons.gesture_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Detección Manos',
                    value: '$detectPct%',
                    subtitle:
                        '${result.validFrames}/${result.totalEvaluatedFrames} fr',
                    icon: Icons.back_hand_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Reproductor del intento con overlay de MediaPipe
            if (vm.attemptTempVideoPath != null) ...[
              const Text(
                'Revisión de tu Grabación',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              PracticeAttemptPlayer(
                videoPath: vm.attemptTempVideoPath!,
                frames: vm.attemptFrames,
              ),
              const SizedBox(height: 20),
            ],

            // Acciones
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => vm.startPracticeSetup(),
              icon: const Icon(Icons.replay_rounded),
              label: const Text(
                'Intentar de Nuevo (6s)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.glassBorder),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => vm.backToDemonstration(),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Ver Demostración Guía'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    String? subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.cyanAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}
