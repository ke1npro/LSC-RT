import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../widgets/glass_top_bar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsVm = context.watch<SettingsViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Contenido desplazable
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 40),
              children: [
                // SECCIÓN 1: SUPERPOSICIONES Y VISIÓN
                _buildSectionHeader('SUPERPOSICIONES Y VISIÓN'),
                const SizedBox(height: 10),
                _buildCard([
                  _buildSwitchTile(
                    icon: Icons.hub_outlined,
                    iconColor: AppColors.cyanAccent,
                    title: 'Overlay MediaPipe en Traducción',
                    subtitle:
                        'Dibuja el esqueleto anatómico y articulaciones en tiempo real.',
                    value: settingsVm.showMediaPipeOverlay,
                    onChanged: (val) =>
                        settingsVm.setShowMediaPipeOverlay(val),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildSwitchTile(
                    icon: Icons.crop_free_rounded,
                    iconColor: AppColors.cyanAccent,
                    title: 'Detección y Visor Facial',
                    subtitle:
                        'Muestra el visor tecnológico de 4 esquinas sobre el rostro.',
                    value: settingsVm.showFaceDetection,
                    onChanged: (val) => settingsVm.setShowFaceDetection(val),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildSwitchTile(
                    icon: Icons.school_outlined,
                    iconColor: AppColors.guideViolet,
                    title: 'Overlay MediaPipe en Enseñanza',
                    subtitle:
                        'Superpone tu esqueleto real sobre el modelo guía del tutor.',
                    value: settingsVm.showTeachingMediaPipeOverlay,
                    onChanged: (val) =>
                        settingsVm.setShowTeachingMediaPipeOverlay(val),
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 2: HOJA DE RUTA / FUTURAS MEJORAS
                _buildSectionHeader('PRÓXIMAS FUNCIONALIDADES (HOJA DE RUTA)'),
                const SizedBox(height: 10),
                _buildCard([
                  _buildDisabledTile(
                    icon: Icons.record_voice_over_outlined,
                    title: 'Texto a Voz en Tiempo Real (TTS)',
                    subtitle:
                        'Pronunciación sintética de letras y frases detectadas.',
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildDisabledTile(
                    icon: Icons.accessibility_new_outlined,
                    title: 'Avatar 3D Completo (Texto ➔ Señas)',
                    subtitle:
                        'Modelo tridimensional de traducción bidireccional.',
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildDisabledTile(
                    icon: Icons.timeline_outlined,
                    title: 'Reconocimiento Continuo de Frases (LSTM)',
                    subtitle:
                        'Ventana temporal deslizante para oraciones en movimiento.',
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildDisabledTile(
                    icon: Icons.vibration_outlined,
                    title: 'Feedback Háptico en Corrección',
                    subtitle:
                        'Vibración háptica ante desvíos posturales del usuario.',
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 3: INFORMACIÓN DEL SISTEMA
                _buildSectionHeader('INFORMACIÓN DEL SISTEMA'),
                const SizedBox(height: 10),
                _buildCard([
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LSC RT — Reconocimiento en Tiempo Real',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Versión 2.0.0 (Clean Architecture + Two-Bone IK)\nMotor de Visión: MediaPipe Hand Landmarker + MLKit Face\nClasificación: Distancia Euclidiana en Espacio Normalizado',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),

          // Barra Superior Flotante
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassTopBar(
              title: 'Configuración',
              subtitle: 'Preferencias de Visión y Sistema',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.cyanAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ),
      value: value,
      activeTrackColor: iconColor,
      activeThumbColor: Colors.white,
      onChanged: onChanged,
    );
  }

  Widget _buildDisabledTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      enabled: false,
      leading: Icon(icon, color: AppColors.textMuted, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Pronto',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
