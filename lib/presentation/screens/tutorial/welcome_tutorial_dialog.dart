import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class WelcomeTutorialDialog extends StatelessWidget {
  const WelcomeTutorialDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const WelcomeTutorialDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xF5121727),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      title: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyanAccent.withValues(alpha: 0.14),
              border: Border.all(
                color: AppColors.cyanAccent.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppColors.cyanAccent,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Bienvenido a LSC RT',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Text(
          'Tu diccionario inicia desde 0 palabras para adaptarse exactamente a tus propias señas, sin conexión a internet.\n\n'
          '¿Quieres hacer un recorrido rápido de 5 pasos para aprender a grabar, recortar, traducir y practicar? '
          'También podrás volver a abrirlo cuando quieras desde Ajustes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Ahora no',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Ver tutorial',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
