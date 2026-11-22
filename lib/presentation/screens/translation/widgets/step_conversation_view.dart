import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/conversation_turn.dart';
import '../../../viewmodels/step_conversation_viewmodel.dart';
import '../../../widgets/camera_viewport.dart';
import '../../../widgets/painters/body_pose_painter.dart';

class StepConversationView extends StatefulWidget {
  const StepConversationView({super.key});

  @override
  State<StepConversationView> createState() => _StepConversationViewState();
}

class _StepConversationViewState extends State<StepConversationView> {
  final TextEditingController _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StepConversationViewModel>();

    return Column(
      children: [
        if (vm.history.isNotEmpty) _buildHistoryBanner(vm),
        Expanded(child: _buildPhaseContent(context, vm)),
      ],
    );
  }

  Widget _buildHistoryBanner(StepConversationViewModel vm) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: vm.toggleHistoryExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined,
                      color: AppColors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Historial de conversación (${vm.history.length})',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (vm.isHistoryExpanded)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: vm.clearHistory,
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(
                          color: AppColors.redError,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  Icon(
                    vm.isHistoryExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (vm.isHistoryExpanded) ...[
            const Divider(height: 1, color: AppColors.glassBorder),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                shrinkWrap: true,
                itemCount: vm.history.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final turn = vm.history[index];
                  return _buildHistoryTile(vm, turn);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTile(
      StepConversationViewModel vm, ConversationTurn turn) {
    final accent = turn.isFromSigner ? AppColors.cyanAccent : AppColors.mintGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Icon(
            turn.isFromSigner
                ? Icons.sign_language_rounded
                : Icons.accessibility_new_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turn.isFromSigner ? 'Señas -> Texto' : 'Respuesta -> Avatar',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  turn.text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (turn.isFromSigner || turn.hasReplayableAvatar)
            IconButton(
              tooltip: turn.isFromSigner ? 'Escuchar voz' : 'Reproducir Avatar',
              icon: Icon(
                turn.isFromSigner
                    ? Icons.volume_up_rounded
                    : Icons.play_circle_outline_rounded,
                color: accent,
                size: 20,
              ),
              onPressed: () => vm.replayHistoryTurn(turn),
            ),
        ],
      ),
    );
  }

  Widget _buildPhaseContent(BuildContext context, StepConversationViewModel vm) {
    switch (vm.phase) {
      case StepConversationPhase.readyToRecord:
      case StepConversationPhase.countdown:
      case StepConversationPhase.recording:
        return _buildCameraPhase(vm);
      case StepConversationPhase.processing:
        return _buildProcessingPhase(vm);
      case StepConversationPhase.translatedReview:
        return _buildTranslatedReviewPhase(vm);
      case StepConversationPhase.composeReply:
        return _buildComposeReplyPhase(vm);
      case StepConversationPhase.avatarPlayback:
        return _buildAvatarPlaybackPhase(vm);
    }
  }

  // PASO 1: GRABAR SEÑAS (< 60s @ 30 FPS)
  Widget _buildCameraPhase(StepConversationViewModel vm) {
    final hasSigns = vm.dictionarySigns.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraViewport(
              controller: vm.cameraDataSource.controller,
              isFrontCamera: vm.isFrontCamera,
              isSwitching: vm.isCameraSwitching,
              isPermissionDenied: vm.isCameraPermissionDenied,
              errorMessage: vm.cameraErrorMessage,
              onRetry: () => vm.retryCamera(),
            ),

            // Barra informativa superior dentro del visor
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasSigns
                            ? 'Paso 1: Graba hasta 60s (${vm.dictionarySigns.length} señas en diccionario)'
                            : 'Diccionario vacío: graba señas primero en la pestaña Diccionario',
                        style: TextStyle(
                          color: hasSigns ? Colors.white : AppColors.amberWarning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (vm.phase == StepConversationPhase.readyToRecord)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.cameraswitch_rounded,
                            color: AppColors.cyanAccent, size: 20),
                        onPressed: () => vm.switchCamera(),
                      ),
                  ],
                ),
              ),
            ),

            // Cuenta regresiva 3-2-1
            if (vm.phase == StepConversationPhase.countdown)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Text(
                    '${vm.countdownSeconds}',
                    style: const TextStyle(
                      color: AppColors.cyanAccent,
                      fontSize: 100,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

            // Controles inferiores
            Positioned(
              bottom: 18,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  if (vm.phase == StepConversationPhase.recording) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (vm.recordingSeconds /
                                StepConversationViewModel.maxRecordingSeconds)
                            .clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.redAccent),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${vm.recordingSeconds.toStringAsFixed(1)}s / ${StepConversationViewModel.maxRecordingSeconds.toInt()}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Detener y Traducir'),
                      onPressed: () => vm.stopRecordingAndTranslate(),
                    ),
                  ] else if (vm.phase == StepConversationPhase.readyToRecord) ...[
                    GestureDetector(
                      onTap: () => vm.startCountdown(),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: hasSigns
                              ? Colors.redAccent
                              : Colors.grey.shade700,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.fiber_manual_record,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Toca para grabar mensaje en señas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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

  // PROCESAMIENTO OFFLINE A 30 FPS
  Widget _buildProcessingPhase(StepConversationViewModel vm) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            const Text(
              'Analizando grabación a 30 FPS',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Extrayendo puntos de las manos y segmentando señas por puntos finales...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
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
    );
  }

  // PASO 2: REVISIÓN DEL TEXTO TRADUCIDO + TTS
  Widget _buildTranslatedReviewPhase(StepConversationViewModel vm) {
    final result = vm.lastTranslationResult;
    final hasTranslation = result?.hasTranslation ?? false;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: hasTranslation
                  ? AppColors.cyanAccent.withValues(alpha: 0.5)
                  : AppColors.amberWarning.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasTranslation
                        ? Icons.translate_rounded
                        : Icons.info_outline_rounded,
                    color: hasTranslation
                        ? AppColors.cyanAccent
                        : AppColors.amberWarning,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Paso 2: Mensaje Traducido',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                hasTranslation
                    ? result!.fullText
                    : 'No se reconocieron señas de tu diccionario en esta grabación.',
                style: TextStyle(
                  color: hasTranslation
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: hasTranslation ? 24 : 15,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (hasTranslation) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: result!.segments
                      .map(
                        (seg) => Chip(
                          backgroundColor: Colors.black26,
                          side: const BorderSide(color: AppColors.glassBorder),
                          label: Text(
                            '${seg.word} (${seg.confidencePercent}%)',
                            style: const TextStyle(
                              color: AppColors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.cyanAccent,
                    side: const BorderSide(color: AppColors.cyanAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => vm.speakTranslatedText(),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('Escuchar traducción (TTS)'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyanAccent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            _replyController.clear();
            vm.proceedToComposeReply();
          },
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text(
            'Escribir Respuesta para Avatar',
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
          onPressed: () => vm.startNextTurn(),
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Volver a grabar'),
        ),
      ],
    );
  }

  // PASO 3: ESCRIBIR RESPUESTA EN TEXTO
  Widget _buildComposeReplyPhase(StepConversationViewModel vm) {
    final dictWords = vm.dictionarySigns.map((s) => s.word).toSet().toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Paso 3: Escribe tu respuesta',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'La app buscará frases y palabras de tu diccionario para animar la respuesta en el Avatar.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _replyController,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Ej. Buenos días gracias...',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceGlass,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.cyanAccent),
            ),
          ),
        ),
        if (vm.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            vm.errorMessage!,
            style: const TextStyle(color: AppColors.redError, fontSize: 12),
          ),
        ],
        if (dictWords.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Señas disponibles en tu diccionario (toca para agregar):',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dictWords
                .map(
                  (w) => ActionChip(
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.glassBorder),
                    label: Text(
                      w,
                      style: const TextStyle(
                        color: AppColors.cyanAccent,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () {
                      final curr = _replyController.text.trim();
                      _replyController.text = curr.isEmpty ? w : '$curr $w';
                      _replyController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _replyController.text.length),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyanAccent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => vm.submitReplyText(_replyController.text),
          icon: const Icon(Icons.accessibility_new_rounded),
          label: const Text(
            'Traducir Respuesta a Avatar',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // PASO 4: REPRODUCCIÓN DE RESPUESTA EN AVATAR / ESQUELETO
  Widget _buildAvatarPlaybackPhase(StepConversationViewModel vm) {
    final response = vm.composedResponse;
    final hasAnimation = vm.totalPlaybackFrames > 0;
    final activeWord = vm.currentPlayingWord;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        const Text(
          'Paso 4: Respuesta en Señas (Avatar)',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 290,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: hasAnimation
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final pose = vm.buildCurrentAvatarPose(size);
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
                          ),
                        if (activeWord.isNotEmpty)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.cyanAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.cyanAccent),
                              ),
                              child: Text(
                                activeWord,
                                style: const TextStyle(
                                  color: AppColors.cyanAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: vm.cyclePlaybackSpeed,
                                child: Text(
                                  '${vm.playbackSpeed}x',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.cyanAccent,
                                  foregroundColor: Colors.black,
                                ),
                                icon: Icon(
                                  vm.isPlayingAvatar
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: vm.toggleAvatarPlayPause,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                )
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Ninguna de las palabras escritas tiene seña grabada aún en tu diccionario.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
        ),
        if (response != null && response.missingWords.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amberWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.amberWarning),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.amberWarning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sin seña grabada aún: ${response.missingWords.join(", ")}',
                    style: const TextStyle(
                      color: AppColors.amberWarning,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyanAccent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => vm.startNextTurn(),
          icon: const Icon(Icons.videocam_rounded),
          label: const Text(
            'Siguiente Turno (Grabar Señas)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
