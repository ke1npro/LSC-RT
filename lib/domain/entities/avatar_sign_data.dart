import 'package:flutter/material.dart';

/// Configuración estética del Avatar cinemático.
/// Diseñada modularmente para permitir futuras personalizaciones de estilos
/// (Neón futurista, Anatómico, Vectorial, Malla 3D) sin alterar la lógica de movimiento.
class AvatarTheme {
  final Color torsoColor;
  final Color leftArmColor;
  final Color rightArmColor;
  final Color leftHandColor;
  final Color rightHandColor;
  final Color headColor;
  final Color jointColor;
  final Color trailColor;
  final double jointRadius;
  final double boneWidth;
  final bool showTrail;
  final int trailLength;
  final double glowSigma;

  const AvatarTheme({
    this.torsoColor = const Color(0xFF00F2FE),
    this.leftArmColor = const Color(0xFFFFBE0B),
    this.rightArmColor = const Color(0xFF00F59B),
    this.leftHandColor = const Color(0xFFFFBE0B),
    this.rightHandColor = const Color(0xFF00F59B),
    this.headColor = const Color(0xFF4FACFE),
    this.jointColor = Colors.white,
    this.trailColor = const Color(0xFF00F2FE),
    this.jointRadius = 4.0,
    this.boneWidth = 3.5,
    this.showTrail = true,
    this.trailLength = 8,
    this.glowSigma = 6.0,
  });

  /// Preset Neón Futurista (por defecto)
  factory AvatarTheme.neon() => const AvatarTheme();

  /// Preset Didáctico Anatómico de Alto Contraste
  factory AvatarTheme.highContrast() => const AvatarTheme(
        torsoColor: Color(0xFFE2E8F0),
        leftArmColor: Color(0xFFF59E0B),
        rightArmColor: Color(0xFF10B981),
        leftHandColor: Color(0xFFF59E0B),
        rightHandColor: Color(0xFF10B981),
        headColor: Color(0xFF38BDF8),
        jointColor: Colors.white,
        trailColor: Color(0xFF38BDF8),
        jointRadius: 4.5,
        boneWidth: 4.0,
        showTrail: true,
        trailLength: 6,
        glowSigma: 0.0,
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
    if (json['pose'] != null) {
      (json['pose'] as Map<String, dynamic>).forEach((k, v) {
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
