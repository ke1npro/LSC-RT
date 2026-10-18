import 'package:flutter/material.dart';
import '../../../../core/constants/lsc_alphabet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../viewmodels/translation_viewmodel.dart';

class CalibrationSheet extends StatefulWidget {
  final TranslationViewModel viewModel;

  const CalibrationSheet({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, TranslationViewModel viewModel) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CalibrationSheet(viewModel: viewModel),
    );
  }

  @override
  State<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<CalibrationSheet> {
  late String _selectedLetter;

  @override
  void initState() {
    super.initState();
    _selectedLetter = widget.viewModel.targetLetter;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
          left: BorderSide(color: AppColors.glassBorder),
          right: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: AppColors.cyanAccent, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Calibración LSC',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                splashRadius: 20,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Personaliza el reconocimiento grabando la postura de tu mano para una letra del abecedario.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Selector de Letra
          DropdownButtonFormField<String>(
            initialValue: _selectedLetter,
            dropdownColor: AppColors.surface,
            decoration: InputDecoration(
              labelText: 'Letra a calibrar',
              labelStyle: const TextStyle(color: AppColors.cyanAccent),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.cyanAccent),
              ),
            ),
            items: LscAlphabet.letters.map((l) {
              return DropdownMenuItem(
                value: l,
                child: Text(
                  'Letra $l',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedLetter = val);
              }
            },
          ),
          const SizedBox(height: 20),

          // Botón principal de grabación
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 18),
              label: Text(
                'Grabar postura para "$_selectedLetter"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.viewModel.startCalibration(_selectedLetter);
              },
            ),
          ),
          const SizedBox(height: 12),

          // Botón para limpiar calibraciones
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textMuted),
              label: const Text(
                'Restablecer calibraciones a fábrica',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('¿Restablecer calibraciones?'),
                    content: const Text(
                      'Se borrarán las muestras personalizadas y se cargarán las de fábrica.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Restablecer', style: TextStyle(color: AppColors.redError)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await widget.viewModel.clearAllCustomCalibrations();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
