import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/avatar_sign_data.dart';
import '../../viewmodels/avatar_viewmodel.dart';
import '../../widgets/glass_top_bar.dart';
import 'widgets/avatar_playback_dialog.dart';

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<AvatarViewModel>();
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
    final avatarVm = context.watch<AvatarViewModel>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Contenido principal deslizable
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 80, 20, bottomPadding + 20),
              children: [
                // 1. Panel de Construcción de la Frase
                _buildSentenceBuilderCard(context, avatarVm),

                const SizedBox(height: 20),

                // 2. Buscador y Filtro por Categoría
                _buildSearchAndFilters(avatarVm),

                const SizedBox(height: 16),

                // 3. Catálogo de Palabras Calibradas
                _buildSignsCatalog(avatarVm),
              ],
            ),
          ),

          // Barra Superior Flotante Glassmorphism
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Avatar LSC',
              subtitle: 'Texto a Señas en Tiempo Real',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceBuilderCard(
      BuildContext context, AvatarViewModel viewModel) {
    final hasWords = viewModel.sentenceSequence.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasWords
              ? AppColors.cyanAccent.withValues(alpha: 0.4)
              : AppColors.glassBorder,
        ),
        boxShadow: hasWords
            ? [
                BoxShadow(
                  color: AppColors.cyanAccent.withValues(alpha: 0.1),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  color: AppColors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Frase para el Avatar',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (hasWords)
                TextButton(
                  onPressed: () => viewModel.clearSentence(),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Limpiar',
                    style: TextStyle(
                      color: AppColors.redError,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenedor de palabras seleccionadas
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: !hasWords
                ? const Center(
                    child: Text(
                      'Toca las palabras inferiores para componer una secuencia en LSC.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(viewModel.sentenceSequence.length,
                        (index) {
                      final sign = viewModel.sentenceSequence[index];
                      return Chip(
                        label: Text(
                          sign.displayName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor:
                            AppColors.cyanAccent.withValues(alpha: 0.18),
                        side: const BorderSide(
                            color: AppColors.cyanAccent, width: 1),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteIconColor: AppColors.textSecondary,
                        onDeleted: () => viewModel.removeWordAt(index),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }),
                  ),
          ),

          const SizedBox(height: 14),

          // Botón Interpretar con Avatar
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: hasWords
                  ? () => AvatarPlaybackDialog.show(context, viewModel)
                  : null,
              icon: const Icon(Icons.play_circle_fill_rounded, size: 22),
              label: Text(
                hasWords
                    ? 'Interpretar con Avatar (${viewModel.sentenceSequence.length} palabras)'
                    : 'Selecciona palabras para interpretar',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                disabledForegroundColor: AppColors.textMuted,
                elevation: hasWords ? 4 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(AvatarViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            onChanged: (val) => viewModel.setSearchQuery(val),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar seña por nombre...',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textSecondary, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppColors.textSecondary, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        viewModel.setSearchQuery('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Filtro horizontal por categoría
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: viewModel.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = viewModel.categories[index];
              final isSelected = viewModel.selectedCategory == cat;
              return ChoiceChip(
                label: Text(
                  cat,
                  style: TextStyle(
                    color:
                        isSelected ? Colors.black : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.cyanAccent,
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color:
                      isSelected ? AppColors.cyanAccent : AppColors.glassBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: (_) => viewModel.setSelectedCategory(cat),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignsCatalog(AvatarViewModel viewModel) {
    final signs = viewModel.filteredSigns;

    if (signs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Text(
          'No se encontraron señas con ese criterio.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'PALABRAS DISPONIBLES',
              style: TextStyle(
                color: AppColors.cyanAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              '${signs.length} señas',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: signs.map((sign) {
            return _buildSignChip(sign, viewModel);
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSignChip(AvatarSignData sign, AvatarViewModel viewModel) {
    final isBimanual = sign.isBimanual;

    return InkWell(
      onTap: () => viewModel.addWordToSentence(sign),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isBimanual
                    ? AppColors.amberWarning.withValues(alpha: 0.15)
                    : AppColors.mintGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isBimanual ? Icons.pan_tool_alt_rounded : Icons.back_hand_rounded,
                color: isBimanual ? AppColors.amberWarning : AppColors.mintGreen,
                size: 14,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sign.displayName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.add_rounded,
              color: AppColors.cyanAccent,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
