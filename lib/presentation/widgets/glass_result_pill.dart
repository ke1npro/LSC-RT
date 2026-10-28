import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/sign_prediction.dart';

class GlassResultPill extends StatelessWidget {
  final SignPrediction? prediction;
  final bool hasHand;
  final bool isCalibrationAvailable;

  const GlassResultPill({
    super.key,
    required this.prediction,
    required this.hasHand,
    this.isCalibrationAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              // Letra o palabra reconocida
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: prediction != null && prediction!.isRecognized
                      ? AppColors.cyanAccent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: prediction != null && prediction!.isRecognized
                        ? AppColors.cyanAccent.withValues(alpha: 0.5)
                        : AppColors.glassBorder,
                  ),
                ),
                child: Text(
                  prediction?.label ?? (hasHand ? '?' : '—'),
                  style: TextStyle(
                    color: prediction != null && prediction!.isRecognized
                        ? AppColors.cyanAccent
                        : AppColors.textSecondary,
                    fontSize: (prediction?.label.length ?? 0) > 4 ? 14 : 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),

              // Información textual y barra de confianza
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !hasHand
                          ? 'Esperando mano...'
                          : (prediction != null && prediction!.isRecognized)
                              ? 'Seña Detectada'
                              : 'Analizando postura...',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (hasHand && prediction != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: prediction!.confidence.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            prediction!.confidence > 0.80
                                ? AppColors.mintGreen
                                : (prediction!.confidence > 0.60
                                    ? AppColors.amberWarning
                                    : AppColors.redError),
                          ),
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Coincidencia: ${(prediction!.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Coloca tu mano frente a la cámara',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Botón de Calibración: Marcado como placeholder NO funcional
              Tooltip(
                message: 'Calibración de palabras (En confirmación - Próximamente)',
                child: Opacity(
                  opacity: 0.45,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Calibración de palabras en espera de confirmación. Próximamente.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
  }
}
