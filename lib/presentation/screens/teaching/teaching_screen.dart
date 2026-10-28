import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/avatar_theme.dart';
import '../../../domain/entities/avatar_sign_data.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/teaching_viewmodel.dart';
import '../../widgets/avatar/avatar_pose_painter.dart';
import '../../widgets/camera_viewport.dart';
import '../../widgets/glass_top_bar.dart';
import '../../widgets/painters/body_pose_painter.dart';

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
    final teachingVm = context.watch<TeachingViewModel>();
    final settingsVm = context.watch<SettingsViewModel>();

    switch (teachingVm.mode) {
      case TeachingMode.catalog:
        return _buildCatalogView(context, teachingVm);
      case TeachingMode.demonstration:
        return _buildDemonstrationView(context, teachingVm);
      case TeachingMode.practice:
        return _buildPracticeView(context, teachingVm, settingsVm);
    }
  }

  // VISTA 1: CATÁLOGO DE SELECCIÓN DE SEÑA
  Widget _buildCatalogView(BuildContext context, TeachingViewModel vm) {
    final signs = vm.filteredSigns;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
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
                              'Aprende Lengua de Señas',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Selecciona una seña para estudiar su movimiento con el avatar y practicar con la cámara.',
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
                      hintText: 'Buscar seña para aprender...',
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
                            color:
                                isSelected ? Colors.black : AppColors.textSecondary,
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

                // Lista de señas
                if (signs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(40),
                    alignment: Alignment.center,
                    child: const Text(
                      'No se encontraron señas disponibles.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: signs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final sign = signs[index];
                      return _buildSignCard(context, sign, vm);
                    },
                  ),
              ],
            ),
          ),

          // Barra Superior Flotante
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Enseñanza LSC',
              subtitle: 'Catálogo de Aprendizaje Guiado',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignCard(
      BuildContext context, AvatarSignData sign, TeachingViewModel vm) {
    return InkWell(
      onTap: () => vm.selectSign(sign),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cyanAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.cyanAccent.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.accessibility_new_rounded,
                color: AppColors.cyanAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sign.displayName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sign.category,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sign.isBimanual ? 'Bimanual' : 'Unimanual',
                        style: TextStyle(
                          color: sign.isBimanual
                              ? AppColors.amberWarning
                              : AppColors.mintGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // VISTA 2: DEMOSTRACIÓN DIDÁCTICA CON EL AVATAR
  Widget _buildDemonstrationView(BuildContext context, TeachingViewModel vm) {
    final sign = vm.selectedSign;
    if (sign == null) return const SizedBox.shrink();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 80, 20, bottomPadding + 20),
              children: [
                // 1. Visor del Avatar en bucle
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    height: 340,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF151D33), Color(0xFF0B1020)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.cyanAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          size: Size.infinite,
                          painter: AvatarPosePainter(
                            frame: vm.currentDemoFrame,
                            theme: AvatarTheme.character(),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Text(
                              'Demostración en Bucle',
                              style: TextStyle(
                                color: AppColors.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // 2. Ficha Pedagógica e Instrucciones
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            sign.displayName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.cyanAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sign.category,
                              style: const TextStyle(
                                color: AppColors.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.info_outline_rounded,
                        'Descripción',
                        sign.pedagogicalMetadata.description,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow(
                        Icons.front_hand_outlined,
                        'Configuración de Mano',
                        sign.pedagogicalMetadata.handshapeDescription,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow(
                        Icons.swap_calls_rounded,
                        'Movimiento',
                        sign.pedagogicalMetadata.movementDescription,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow(
                        Icons.tips_and_updates_outlined,
                        'Consejo Pedagógico',
                        sign.pedagogicalMetadata.instructions,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 3. Botón de Acción Principal: "¡Inténtalo tú!"
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => vm.startPractice(),
                    icon: const Icon(Icons.videocam_rounded, size: 24),
                    label: const Text(
                      '¡Inténtalo tú!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: Colors.black,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barra Superior Flotante con Botón Atrás
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Tutor LSC',
              subtitle: 'Aprender: ${sign.displayName}',
              leadingAction: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.cyanAccent),
                onPressed: () => vm.backToCatalog(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.cyanAccent, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // VISTA 3: MODO "¡INTÉNTALO TÚ!" CON CÁMARA Y PORCENTAJE DE COINCIDENCIA
  Widget _buildPracticeView(
      BuildContext context, TeachingViewModel vm, SettingsViewModel settingsVm) {
    final sign = vm.selectedSign;
    final score = vm.matchScore;
    final scorePercent = (score * 100).toInt();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Visor de Cámara con BodyPosePainter interactivo
          CameraViewport(
            controller: vm.cameraDataSource.controller,
            isFrontCamera: vm.isFrontCamera,
            isSwitching: vm.isCameraSwitching,
            isPermissionDenied: vm.isCameraPermissionDenied,
            errorMessage: vm.cameraErrorMessage,
            onRetry: () => vm.retryCamera(),
            onSizeChanged: (size) => vm.setViewportSize(size),
            overlay: CustomPaint(
              size: Size.infinite,
              painter: BodyPosePainter(
                pose: vm.userPose,
                showOverlay: true,
                showFace: settingsVm.showFaceDetection,
                isMirrored: vm.isFrontCamera,
              ),
            ),
          ),

          // 2. Mini Visor Flotante del Avatar de Referencia (Picture in Picture)
          Positioned(
            top: 86,
            right: 16,
            child: Container(
              width: 110,
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0xF20A0F1D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.cyanAccent.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size.infinite,
                    painter: AvatarPosePainter(
                      frame: vm.currentDemoFrame,
                      theme: const AvatarTheme(showBackdrop: false),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Guía: ${sign?.displayName ?? ""}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.cyanAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Barra Superior con Botón Atrás
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: '¡Inténtalo tú!',
              subtitle: 'Práctica: ${sign?.displayName ?? ""}',
              isOnline: vm.isInitialized,
              onSwitchCamera: () => vm.switchCamera(),
              leadingAction: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.cyanAccent),
                onPressed: () => vm.backToDemonstration(),
              ),
            ),
          ),

          // 4. Pastilla Inferior de Coincidencia en Tiempo Real
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xF2121727),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.glassBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                          children: [
                            // Medidor circular de coincidencia
                            Container(
                              width: 54,
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (score > 0.75
                                        ? AppColors.mintGreen
                                        : AppColors.cyanAccent)
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: score > 0.75
                                      ? AppColors.mintGreen
                                      : (score > 0.50
                                          ? AppColors.amberWarning
                                          : AppColors.redError),
                                  width: 2.0,
                                ),
                              ),
                              child: Text(
                                '$scorePercent%',
                                style: TextStyle(
                                  color: score > 0.75
                                      ? AppColors.mintGreen
                                      : (score > 0.50
                                          ? AppColors.amberWarning
                                          : AppColors.redError),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Feedback textual y barra
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    !vm.hasUserHand
                                        ? 'Coloca tu mano en el visor'
                                        : (score > 0.75
                                            ? '¡Excelente coincidencia!'
                                            : (score > 0.50
                                                ? 'Bien, afina la postura'
                                                : 'Alinea los dedos con la guía')),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: score.clamp(0.0, 1.0),
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        score > 0.75
                                            ? AppColors.mintGreen
                                            : (score > 0.50
                                                ? AppColors.amberWarning
                                                : AppColors.redError),
                                      ),
                                      minHeight: 6,
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
        ],
      ),
    );
  }
}
