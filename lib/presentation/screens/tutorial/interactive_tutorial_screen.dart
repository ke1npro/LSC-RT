import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class _TutorialStepData {
  final IconData icon;
  final Color accentColor;
  final String badge;
  final String title;
  final String description;
  final List<String> highlights;

  const _TutorialStepData({
    required this.icon,
    required this.accentColor,
    required this.badge,
    required this.title,
    required this.description,
    required this.highlights,
  });
}

class InteractiveTutorialScreen extends StatefulWidget {
  const InteractiveTutorialScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const InteractiveTutorialScreen(),
      ),
    );
  }

  @override
  State<InteractiveTutorialScreen> createState() =>
      _InteractiveTutorialScreenState();
}

class _InteractiveTutorialScreenState extends State<InteractiveTutorialScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_TutorialStepData> _steps = [
    _TutorialStepData(
      icon: Icons.auto_awesome_rounded,
      accentColor: AppColors.cyanAccent,
      badge: 'Paso 1 de 5',
      title: 'Bienvenido a LSC RT',
      description:
          'La aplicación arranca con 0 palabras precargadas para que construyas tu propio banco de Lengua de Señas Colombiana desde cero, adaptado a tu forma real de señar y sin necesidad de internet.',
      highlights: [
        'Inicio limpio: cada palabra vive en tu diccionario personal.',
        'Funciona 100% offline directamente en tu teléfono.',
        'Puedes avanzar deslizando o usando los botones inferiores.',
      ],
    ),
    _TutorialStepData(
      icon: Icons.videocam_rounded,
      accentColor: AppColors.cyanAccent,
      badge: 'Paso 2 de 5',
      title: 'Graba y recorta tus señas',
      description:
          'En la pestaña Diccionario, pulsa "Grabar Seña", indica si usa 1 o 2 manos y registra un clip de hasta 6 segundos con cuenta regresiva 3-2-1.',
      highlights: [
        'Ajusta inicio y fin viendo el esqueleto MediaPipe sobre tu video.',
        'Graba de 1 a 5 tomas: el sistema elige la de mayor % de detección.',
        'Solo las muestras con al menos 70% de detección se guardan.',
      ],
    ),
    _TutorialStepData(
      icon: Icons.translate_rounded,
      accentColor: AppColors.mintGreen,
      badge: 'Paso 3 de 5',
      title: 'Traducción en tiempo real',
      description:
          'La pestaña Traducción compara en vivo los movimientos de tus manos contra las señas guardadas en tu diccionario, sin palabras preprogramadas.',
      highlights: [
        'Mientras haya 0 señas verás el aviso de diccionario vacío.',
        'Soporta señas de 1 y 2 manos con barra de coincidencia en vivo.',
        'Las últimas palabras detectadas aparecen en la cinta inferior.',
      ],
    ),
    _TutorialStepData(
      icon: Icons.school_rounded,
      accentColor: AppColors.guideViolet,
      badge: 'Paso 4 de 5',
      title: 'Practica en Enseñanza',
      description:
          'Cada seña de tu diccionario aparece automáticamente en Enseñanza para que la estudies y pongas a prueba tu ejecución.',
      highlights: [
        'Observa el esqueleto guía a velocidad 0.5x, 1.0x o 1.5x.',
        'Graba una práctica de 6s para evaluarla cuadro por cuadro offline.',
        'Recibe tu % de confianza en forma, movimiento y visibilidad.',
      ],
    ),
    _TutorialStepData(
      icon: Icons.verified_user_rounded,
      accentColor: AppColors.amberWarning,
      badge: 'Paso 5 de 5',
      title: 'Privacidad y Respaldo',
      description:
          'Tus señas se protegen dentro del dispositivo y los clips de video temporales se eliminan al finalizar para cuidar tu espacio y privacidad.',
      highlights: [
        'Diccionario cifrado en reposo (AES-256-GCM con Android Keystore).',
        'Exporta e importa tu diccionario en JSON desde la pestaña Diccionario.',
        'Puedes volver a abrir este tutorial en Ajustes -> Ayuda y Tutorial.',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _steps.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior: contador y botón Omitir
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGlass,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(
                      '${_currentPage + 1} / ${_steps.length}',
                      style: const TextStyle(
                        color: AppColors.cyanAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Omitir',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Contenido deslizable
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) => _buildStepCard(_steps[index]),
              ),
            ),

            // Indicadores animados de página
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (idx) {
                  final active = idx == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: active ? 24 : 8,
                    decoration: BoxDecoration(
                      color: active
                          ? _steps[_currentPage].accentColor
                          : AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Controles inferiores Anterior / Siguiente o Empezar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                children: [
                  if (_currentPage > 0) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.glassBorder),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _goToPage(_currentPage - 1),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Anterior'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: _currentPage > 0 ? 1 : 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyanAccent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (isLastPage) {
                          Navigator.of(context).pop();
                        } else {
                          _goToPage(_currentPage + 1);
                        }
                      },
                      icon: Icon(
                        isLastPage
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      label: Text(
                        isLastPage ? 'Empezar' : 'Siguiente',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard(_TutorialStepData step) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.accentColor.withValues(alpha: 0.14),
                    border: Border.all(
                      color: step.accentColor.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    step.icon,
                    color: step.accentColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: step.accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    step.badge,
                    style: TextStyle(
                      color: step.accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  step.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                ...step.highlights.map(
                  (point) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: step.accentColor,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              point,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
