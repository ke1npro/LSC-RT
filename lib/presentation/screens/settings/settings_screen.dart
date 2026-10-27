import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/i_vision_repository.dart';
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
                  const Divider(height: 1, color: AppColors.glassBorder),
                  _buildRotationTile(
                    context: context,
                    icon: Icons.screen_rotation_outlined,
                    iconColor: AppColors.cyanAccent,
                    title: 'Orientación del Modelo (MediaPipe)',
                    subtitle:
                        'Compensa el ángulo del sensor para alinear el esqueleto con la pantalla.',
                    currentValue: settingsVm.modelRotationDegrees,
                    onChanged: (val) {
                      settingsVm.setModelRotationDegrees(val);
                      context.read<IVisionRepository>().setRotation(val);
                    },
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 2: GESTIÓN DE DATASET Y RESTAURACIÓN DE FÁBRICA
                _buildSectionHeader('GESTIÓN DE DATASET Y OVERRIDES'),
                const SizedBox(height: 10),
                _buildCard([
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined,
                        color: AppColors.cyanAccent, size: 22),
                    title: const Text(
                      'Dataset Original de Fábrica',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${settingsVm.factorySignsCount} señas canónicas base cargadas de assets.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Activo',
                        style: TextStyle(
                          color: AppColors.mintGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  ListTile(
                    leading: Icon(
                      Icons.tune_outlined,
                      color: settingsVm.hasCustomOverrides
                          ? AppColors.amberWarning
                          : AppColors.textMuted,
                      size: 22,
                    ),
                    title: const Text(
                      'Overrides Personalizados de Usuario',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      settingsVm.hasCustomOverrides
                          ? '${settingsVm.customOverridesCount} señas personalizadas en almacenamiento local.'
                          : 'Sin modificaciones locales (usando valores de fábrica).',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 20),
                        label: const Text(
                          'Restablecer a valores de fábrica',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.redError,
                          side: const BorderSide(color: AppColors.redError),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: const BorderSide(
                                    color: AppColors.glassBorder),
                              ),
                              title: const Text(
                                '¿Restablecer Dataset?',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: const Text(
                                'Se eliminarán todos los overrides y calibraciones locales, restaurando la base de datos de señas canónica de fábrica.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancelar',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.redError,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Restablecer'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await settingsVm.restoreFactoryDataset();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Base de datos restaurada a valores canónicos de fábrica.',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 3: CALIBRACIÓN DE PALABRAS (PLACEHOLDER NO FUNCIONAL)
                _buildSectionHeader(
                    'CALIBRACIÓN DE PALABRAS (EN ESPERA DE CONFIRMACIÓN)'),
                const SizedBox(height: 10),
                _buildCard([
                  ListTile(
                    enabled: false,
                    leading: const Icon(Icons.app_registration_rounded,
                        color: AppColors.textMuted, size: 22),
                    title: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recalibrar Vocabulario Dinámico',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        _PlaceholderBadge(),
                      ],
                    ),
                    subtitle: const Text(
                      'Permitirá reescribir las secuencias de referencia directamente desde la cámara.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.textMuted, size: 18),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                  ListTile(
                    enabled: false,
                    leading: const Icon(Icons.straighten_rounded,
                        color: AppColors.textMuted, size: 22),
                    title: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tolerancia Euclidiana y Filtro DTW',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        _PlaceholderBadge(),
                      ],
                    ),
                    subtitle: const Text(
                      'Ajuste manual del umbral de rechazo para señas de baja confianza.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.textMuted, size: 18),
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 4: HOJA DE RUTA
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
                    icon: Icons.timeline_outlined,
                    title: 'Reconocimiento Continuo de Frases (LSTM)',
                    subtitle:
                        'Ventana temporal deslizante para oraciones en movimiento.',
                  ),
                ]),

                const SizedBox(height: 28),

                // SECCIÓN 5: INFORMACIÓN DEL SISTEMA
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
                          'Versión 2.1.0 (Clean Architecture + Avatar Cinemático)\nMotor de Visión: MediaPipe Hand Landmarker + MLKit Face\nSíntesis: Hermite Cubic Blending (60 FPS)\nClasificación: Distancia Euclidiana en Espacio Normalizado',
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
    );
  }

  Widget _buildRotationTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int currentValue,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: currentValue,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            color: AppColors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('0°')),
            DropdownMenuItem(value: 90, child: Text('90°')),
            DropdownMenuItem(value: 180, child: Text('180°')),
            DropdownMenuItem(value: 270, child: Text('270°')),
          ],
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }
}

class _PlaceholderBadge extends StatelessWidget {
  const _PlaceholderBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amberWarning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.amberWarning.withValues(alpha: 0.4),
        ),
      ),
      child: const Text(
        'Próximamente',
        style: TextStyle(
          color: AppColors.amberWarning,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
