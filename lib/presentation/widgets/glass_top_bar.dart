import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class GlassTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isOnline;
  final VoidCallback? onSwitchCamera;
  final List<Widget>? actions;

  const GlassTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.isOnline = true,
    this.onSwitchCamera,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                // Indicador de estado (pulso verde/cyan)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? AppColors.mintGreen : AppColors.amberWarning,
                    boxShadow: [
                      BoxShadow(
                        color: (isOnline ? AppColors.mintGreen : AppColors.amberWarning)
                            .withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Título y subtítulo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // Acciones adicionales opcionales
                ...?actions,

                // Botón alternar cámara
                if (onSwitchCamera != null)
                  IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios_rounded,
                      color: AppColors.cyanAccent,
                      size: 20,
                    ),
                    splashRadius: 20,
                    tooltip: 'Cambiar cámara',
                    onPressed: onSwitchCamera,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
