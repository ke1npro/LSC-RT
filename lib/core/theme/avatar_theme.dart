import 'package:flutter/material.dart';

/// Configuración estética del Avatar cinemático.
/// Diseñada modularmente para permitir futuras personalizaciones de estilos
/// (Personaje ilustrado, Alto contraste, Malla 3D) sin alterar la lógica de movimiento.
///
/// Para crear un nuevo estilo basta con instanciar [AvatarTheme] con otra paleta
/// (piel, ropa, cabello) o agregar un nuevo factory. El painter solo lee estos campos.
class AvatarTheme {
  // --- Colores de identidad por mano (halo + estela didáctica) ---
  final Color leftHandColor;
  final Color rightHandColor;

  // --- Paleta del personaje ---
  final Color skinColor;
  final Color skinShadeColor;
  final Color shirtColor;
  final Color shirtShadeColor;
  final Color hairColor;
  final Color outlineColor;
  final Color backdropColor;

  // --- Campos legados (se mantienen por compatibilidad de API) ---
  final Color torsoColor;
  final Color leftArmColor;
  final Color rightArmColor;
  final Color headColor;
  final Color jointColor;
  final Color trailColor;
  final double jointRadius;
  final double boneWidth;

  // --- Comportamiento ---
  final bool showTrail;
  final int trailLength;

  /// Intensidad del halo de color de cada mano (0 = sin halo).
  final double glowSigma;

  /// Grosor relativo del contorno del personaje.
  final double outlineScale;

  /// Dibuja el foco de luz detrás del personaje.
  final bool showBackdrop;

  /// Relación de aspecto (ancho/alto) del video fuente del que se extrajeron
  /// las coordenadas normalizadas. Corrige proporciones del cuerpo.
  final double sourceAspect;

  const AvatarTheme({
    this.leftHandColor = const Color(0xFFFFB020),
    this.rightHandColor = const Color(0xFF00E0B0),
    this.skinColor = const Color(0xFFF1C7A3),
    this.skinShadeColor = const Color(0xFFD69E78),
    this.shirtColor = const Color(0xFF3D6FE0),
    this.shirtShadeColor = const Color(0xFF2547A8),
    this.hairColor = const Color(0xFF2A1C16),
    this.outlineColor = const Color(0xFF0B1022),
    this.backdropColor = const Color(0xFF2A3A66),
    this.torsoColor = const Color(0xFF3D6FE0),
    this.leftArmColor = const Color(0xFFFFB020),
    this.rightArmColor = const Color(0xFF00E0B0),
    this.headColor = const Color(0xFFF1C7A3),
    this.jointColor = Colors.white,
    this.trailColor = const Color(0xFF00E5FF),
    this.jointRadius = 4.0,
    this.boneWidth = 3.5,
    this.showTrail = true,
    this.trailLength = 10,
    this.glowSigma = 10.0,
    this.outlineScale = 1.0,
    this.showBackdrop = true,
    this.sourceAspect = 16 / 9,
  });

  /// Preset Personaje ilustrado (por defecto). Se conserva el nombre `neon`
  /// por compatibilidad con código existente.
  factory AvatarTheme.neon() => const AvatarTheme();

  /// Alias legible del preset por defecto.
  factory AvatarTheme.character() => const AvatarTheme();

  /// Preset Didáctico de Alto Contraste (ropa oscura, contorno grueso, sin halo).
  factory AvatarTheme.highContrast() => const AvatarTheme(
        shirtColor: Color(0xFF2B2F3A),
        shirtShadeColor: Color(0xFF16181F),
        hairColor: Color(0xFF111111),
        outlineColor: Color(0xFF000000),
        backdropColor: Color(0xFF3A4256),
        leftHandColor: Color(0xFFFFA000),
        rightHandColor: Color(0xFF00C896),
        glowSigma: 6.0,
        outlineScale: 1.6,
        trailLength: 8,
      );

  /// Preset Esmeralda.
  factory AvatarTheme.emerald() => const AvatarTheme(
        shirtColor: Color(0xFF12A37A),
        shirtShadeColor: Color(0xFF0B6B50),
        hairColor: Color(0xFF4A2E1E),
        skinColor: Color(0xFFC98E68),
        skinShadeColor: Color(0xFFA56E4C),
        backdropColor: Color(0xFF1E4D44),
      );
}
