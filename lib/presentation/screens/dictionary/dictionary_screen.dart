import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/recorded_sign.dart';
import '../../viewmodels/dictionary_viewmodel.dart';
import '../../widgets/glass_top_bar.dart';
import 'recorded_sign_playback_dialog.dart';
import 'sign_recorder_wizard_screen.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DictionaryViewModel>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openRecorder() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SignRecorderWizardScreen()),
    );
    if (!mounted || result != true) return;
    context.read<DictionaryViewModel>().initialize();
  }

  Future<void> _exportDictionary(DictionaryViewModel vm) async {
    final jsonStr = await vm.exportDictionary();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        title: const Text('Exportar Diccionario', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diccionario con ${vm.allSigns.length} señas en formato JSON:',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              height: 140,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: SingleChildScrollView(
                child: Text(
                  jsonStr,
                  style: const TextStyle(color: AppColors.cyanAccent, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar al portapapeles'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Diccionario copiado al portapapeles'),
                  backgroundColor: Color(0xFF00C853),
                ),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _importDictionary(DictionaryViewModel vm) async {
    final textController = TextEditingController();

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        title: const Text('Importar Diccionario JSON', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega el contenido JSON del diccionario exportado previamente:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '{\n  "format": "LSC_OFFLINE_DICTIONARY",\n  ...\n}',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.glassBorder),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              try {
                final count = await vm.importDictionary(textController.text);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop(true);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Se importaron $count señas al diccionario'),
                      backgroundColor: const Color(0xFF00C853),
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Error al importar: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );

    if (success == true && mounted) {
      vm.initialize();
    }
  }

  Future<void> _confirmDelete(DictionaryViewModel vm, RecordedSign sign) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        title: Text('¿Eliminar seña "${sign.word}"?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Esta acción eliminará permanentemente la seña del diccionario local.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await vm.deleteSign(sign.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Seña "${sign.word}" eliminada'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DictionaryViewModel>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final signs = vm.filteredSigns;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyanAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_a_photo_rounded),
        label: const Text(
          'Grabar Seña',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: _openRecorder,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 80, 20, bottomPadding + 90),
              children: [
                // Barra de herramientas: Contador de palabras y botones Exportar / Importar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${vm.allSigns.length} señas registradas',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Exportar JSON',
                          icon: const Icon(Icons.file_upload_outlined, color: AppColors.cyanAccent),
                          onPressed: vm.allSigns.isEmpty ? null : () => _exportDictionary(vm),
                        ),
                        IconButton(
                          tooltip: 'Importar JSON',
                          icon: const Icon(Icons.file_download_outlined, color: AppColors.cyanAccent),
                          onPressed: () => _importDictionary(vm),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Barra de Búsqueda
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por seña o categoría...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              vm.setSearchQuery('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surfaceGlass,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.glassBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (val) => vm.setSearchQuery(val),
                ),

                const SizedBox(height: 12),

                // Filtros Rápidos (Categorías y Manos)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Filtro Manos
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: vm.selectedHandsFilter == null,
                        selectedColor: AppColors.cyanAccent,
                        labelStyle: TextStyle(
                          color: vm.selectedHandsFilter == null ? Colors.black : Colors.white,
                          fontSize: 12,
                        ),
                        onSelected: (_) => vm.setSelectedHandsFilter(null),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('1 Mano'),
                        selected: vm.selectedHandsFilter == 1,
                        selectedColor: AppColors.cyanAccent,
                        labelStyle: TextStyle(
                          color: vm.selectedHandsFilter == 1 ? Colors.black : Colors.white,
                          fontSize: 12,
                        ),
                        onSelected: (_) => vm.setSelectedHandsFilter(1),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('2 Manos'),
                        selected: vm.selectedHandsFilter == 2,
                        selectedColor: AppColors.cyanAccent,
                        labelStyle: TextStyle(
                          color: vm.selectedHandsFilter == 2 ? Colors.black : Colors.white,
                          fontSize: 12,
                        ),
                        onSelected: (_) => vm.setSelectedHandsFilter(2),
                      ),
                      const SizedBox(width: 12),
                      Container(height: 20, width: 1, color: AppColors.glassBorder),
                      const SizedBox(width: 12),

                      // Filtro Categorías
                      ...vm.categories.map((cat) {
                        final isSel = vm.selectedCategory.toLowerCase() == cat.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSel,
                            selectedColor: AppColors.surfaceGlass,
                            side: BorderSide(
                              color: isSel ? AppColors.cyanAccent : AppColors.glassBorder,
                            ),
                            labelStyle: TextStyle(
                              color: isSel ? AppColors.cyanAccent : AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            onSelected: (_) => vm.setSelectedCategory(cat),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Lista de Señas o Estado Vacío
                if (vm.allSigns.isEmpty)
                  _buildEmptyState(context)
                else if (signs.isEmpty)
                  _buildNoResultsState()
                else
                  ...signs.map((sign) => _buildSignCard(context, vm, sign)),
              ],
            ),
          ),

          // Barra Superior Flotante Glassmorphism
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Diccionario LSC',
              subtitle: 'Laboratorio y Banco de Señas Offline',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyanAccent.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.menu_book_rounded, color: AppColors.cyanAccent, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            '0 palabras en el diccionario',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'El sistema inicia en limpio. Comienza grabando tus propias señas desde la cámara con procesamiento offline y validación de calidad.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _openRecorder,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Grabar Primera Seña'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: const Text(
        'No se encontraron señas con los filtros seleccionados.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildSignCard(BuildContext context, DictionaryViewModel vm, RecordedSign sign) {
    final pct = (sign.detectionRate * 100).toStringAsFixed(1);
    final durationSec = (sign.frameCount / sign.fps).toStringAsFixed(1);

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
          onTap: () => RecordedSignPlaybackDialog.show(context, sign),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Ícono de reproducción esqueleto
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.cyanAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),

                // Información central
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
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sign.category,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.cyanAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sign.isBimanual ? '2 Manos' : '1 Mano',
                              style: const TextStyle(
                                color: AppColors.cyanAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$durationSec s (${sign.frameCount} fr)',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Badge de detección %
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x3300C853),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$pct%',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                      onPressed: () => _confirmDelete(vm, sign),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
