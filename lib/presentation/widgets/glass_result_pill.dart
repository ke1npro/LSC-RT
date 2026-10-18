import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/sign_prediction.dart';

class GlassResultPill extends StatelessWidget {
  final SignPrediction? prediction;
  final bool hasHand;
  final VoidCallback? onCalibrateTap;

  const GlassResultPill({
    super.key,
    required this.prediction,
    required this.hasHand,
    this.onCalibrateTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                // Letra reconocida o ícono
                Container(
                  width: 52,
                  height: 52,
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
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
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
                        Text(
                          !hasHand
                              ? 'Coloca tu mano frente a la cámara'
                              : 'Realiza una seña del abecedario',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Botón rápido de calibración
                if (onCalibrateTap != null)
                  IconButton(
                    icon: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.cyanAccent,
                      size: 22,
                    ),
                    tooltip: 'Calibrar Señas',
                    onPressed: onCalibrateTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
