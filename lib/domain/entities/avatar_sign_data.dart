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

/// Punto tridimensional (normalizado 0.0 a 1.0)
class AvatarPoint {
  final double x;
  final double y;
  final double z;

  const AvatarPoint(this.x, this.y, [this.z = 0.0]);

  factory AvatarPoint.fromList(List<dynamic> list) {
    return AvatarPoint(
      (list[0] as num).toDouble(),
      (list[1] as num).toDouble(),
      list.length > 2 ? (list[2] as num).toDouble() : 0.0,
    );
  }

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z};
}

/// Cuadro cinemático individual de una seña (Pose corporal + Manos de 21 puntos)
class AvatarFrame {
  final Map<String, AvatarPoint> pose;
  final List<AvatarPoint>? leftHand;
  final List<AvatarPoint>? rightHand;
  final bool hasLeftHand;
  final bool hasRightHand;

  const AvatarFrame({
    required this.pose,
    this.leftHand,
    this.rightHand,
    required this.hasLeftHand,
    required this.hasRightHand,
  });

  factory AvatarFrame.fromJson(Map<String, dynamic> json) {
    final poseMap = <String, AvatarPoint>{};
    // El banco de movimiento usa la llave 'torso'; se acepta 'pose' por compatibilidad.
    final rawPose = json['pose'] ?? json['torso'];
    if (rawPose != null) {
      (rawPose as Map<String, dynamic>).forEach((k, v) {
        poseMap[k] = AvatarPoint.fromList(v as List<dynamic>);
      });
    }

    List<AvatarPoint>? lh;
    if (json['left_hand'] != null) {
      lh = (json['left_hand'] as List<dynamic>)
          .map((pt) => AvatarPoint.fromList(pt as List<dynamic>))
          .toList();
    }

    List<AvatarPoint>? rh;
    if (json['right_hand'] != null) {
      rh = (json['right_hand'] as List<dynamic>)
          .map((pt) => AvatarPoint.fromList(pt as List<dynamic>))
          .toList();
    }

    return AvatarFrame(
      pose: poseMap,
      leftHand: lh,
      rightHand: rh,
      hasLeftHand: json['has_left_hand'] ?? (lh != null && lh.isNotEmpty),
      hasRightHand: json['has_right_hand'] ?? (rh != null && rh.isNotEmpty),
    );
  }
}

/// Metadata pedagógica e instructiva de una seña
class PedagogicalMetadata {
  final String description;
  final String instructions;
  final String handshapeDescription;
  final String movementDescription;
  final String locationDescription;

  const PedagogicalMetadata({
    required this.description,
    required this.instructions,
    required this.handshapeDescription,
    required this.movementDescription,
    required this.locationDescription,
  });

  factory PedagogicalMetadata.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PedagogicalMetadata(
        description: 'Seña canónica de Lengua de Señas Colombiana.',
        instructions: 'Imita la postura y movimiento del avatar.',
        handshapeDescription: 'Configuración estándar.',
        movementDescription: 'Movimiento fluido.',
        locationDescription: 'Espacio de articulación frontal.',
      );
    }
    return PedagogicalMetadata(
      description: json['description'] ?? 'Seña canónica de LSC.',
      instructions: json['instructions'] ?? 'Imita el movimiento del avatar.',
      handshapeDescription: json['handshape_description'] ?? 'Configuración estándar.',
      movementDescription: json['movement_description'] ?? 'Movimiento canónico.',
      locationDescription: json['location_description'] ?? 'Espacio frontal.',
    );
  }
}

/// Modelo completo de una seña canónica sintetizada para el Avatar
class AvatarSignData {
  final String id;
  final String signId;
  final String displayName;
  final String category;
  final String type; // UNIMANUAL o BIMANUAL
  final int totalFrames;
  final double fps;
  final double durationSeconds;
  final int apexFrame;
  final PedagogicalMetadata pedagogicalMetadata;
  final List<AvatarFrame> frames;

  const AvatarSignData({
    required this.id,
    required this.signId,
    required this.displayName,
    required this.category,
    required this.type,
    required this.totalFrames,
    required this.fps,
    required this.durationSeconds,
    required this.apexFrame,
    required this.pedagogicalMetadata,
    required this.frames,
  });

  bool get isBimanual => type.toUpperCase() == 'BIMANUAL';

  factory AvatarSignData.fromJson(Map<String, dynamic> json) {
    final framesList = (json['frames'] as List<dynamic>?)
            ?.map((f) => AvatarFrame.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];

    return AvatarSignData(
      id: json['id'] ?? '',
      signId: json['sign_id'] ?? json['id'] ?? '',
      displayName: json['display_name'] ?? json['id'] ?? '',
      category: json['category'] ?? 'General',
      type: json['type'] ?? 'UNIMANUAL',
      totalFrames: json['total_frames'] ?? framesList.length,
      fps: (json['fps'] as num?)?.toDouble() ?? 24.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 2.0,
      apexFrame: json['apex_frame'] ?? (framesList.length ~/ 2),
      pedagogicalMetadata: PedagogicalMetadata.fromJson(
        json['pedagogical_metadata'] as Map<String, dynamic>?,
      ),
      frames: framesList,
    );
  }
}
