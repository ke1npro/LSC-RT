import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../domain/entities/avatar_sign_data.dart';

/// Painter de alto rendimiento para el Avatar Cinemático de Lengua de Señas.
/// Arquitectura desacoplada basada en [AvatarTheme], facilitando su sustitución
/// por renderizado 3D, sprites o mallas avanzadas sin alterar la lógica de negocio.
class AvatarPosePainter extends CustomPainter {
  final AvatarFrame? frame;
  final AvatarTheme theme;
  final bool isMirrored;
  final List<Offset> rightHandTrail;
  final List<Offset> leftHandTrail;

  AvatarPosePainter({
    required this.frame,
    this.theme = const AvatarTheme(),
    this.isMirrored = false,
    this.rightHandTrail = const [],
    this.leftHandTrail = const [],
  });

  // Conexiones de los 21 puntos anatómicos de la mano MediaPipe
  static const List<List<int>> handConnections = [
    // Pulgar
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Índice
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Medio
    [9, 10], [10, 11], [11, 12],
    // Anular
    [13, 14], [14, 15], [15, 16],
    // Meñique
    [0, 17], [17, 18], [18, 19], [19, 20],
    // Palma
    [5, 9], [9, 13], [13, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (frame == null) return;

    final width = size.width;
    final height = size.height;

    // 1. Dibujar estelas de movimiento (Motion Trails) si están habilitadas
    if (theme.showTrail) {
      _drawTrail(canvas, rightHandTrail, theme.rightHandColor);
      _drawTrail(canvas, leftHandTrail, theme.leftHandColor);
    }

    // 2. Dibujar Torso y Cabeza
    _drawTorsoAndHead(canvas, width, height);

    // 3. Dibujar Brazos (Cinemática superior)
    _drawArms(canvas, width, height);

    // 4. Dibujar Manos (21 puntos MediaPipe por mano)
    if (frame!.hasLeftHand && frame!.leftHand != null) {
      _drawHand(
        canvas,
        frame!.leftHand!,
        width,
        height,
        boneColor: theme.leftHandColor,
        isLeft: true,
      );
    }

    if (frame!.hasRightHand && frame!.rightHand != null) {
      _drawHand(
        canvas,
        frame!.rightHand!,
        width,
        height,
        boneColor: theme.rightHandColor,
        isLeft: false,
      );
    }
  }

  void _drawTrail(Canvas canvas, List<Offset> trail, Color color) {
    if (trail.length < 2) return;
    for (int i = 0; i < trail.length - 1; i++) {
      final double progress = i / trail.length;
      final paint = Paint()
        ..color = color.withValues(alpha: progress * 0.45)
        ..strokeWidth = theme.boneWidth * progress
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(trail[i], trail[i + 1], paint);
    }
  }

  void _drawTorsoAndHead(Canvas canvas, double width, double height) {
    final pose = frame!.pose;
    final ls = _toOffset(pose['left_shoulder'], width, height);
    final rs = _toOffset(pose['right_shoulder'], width, height);
    final lh = _toOffset(pose['left_hip'], width, height);
    final rh = _toOffset(pose['right_hip'], width, height);
    final nose = _toOffset(pose['nose'], width, height);

    final torsoPaint = Paint()
      ..color = theme.torsoColor
      ..strokeWidth = theme.boneWidth * 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = theme.torsoColor.withValues(alpha: 0.25)
      ..strokeWidth = theme.boneWidth * 2.2
      ..style = PaintingStyle.stroke
      ..maskFilter = theme.glowSigma > 0
          ? ui.MaskFilter.blur(BlurStyle.normal, theme.glowSigma)
          : null;

    // Clavícula
    if (ls != null && rs != null) {
      if (theme.glowSigma > 0) canvas.drawLine(ls, rs, glowPaint);
      canvas.drawLine(ls, rs, torsoPaint);

      // Cuello y Cabeza
      final midShoulder = Offset((ls.dx + rs.dx) / 2, (ls.dy + rs.dy) / 2);
      final headCenter = nose ?? Offset(midShoulder.dx, midShoulder.dy - height * 0.12);

      canvas.drawLine(midShoulder, headCenter, torsoPaint);

      // Cabeza estilizada (óvalo con aura futurista)
      final headRadius = width * 0.085;
      final headPaint = Paint()
        ..color = theme.headColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      final headBorder = Paint()
        ..color = theme.headColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(headCenter, headRadius, headPaint);
      canvas.drawCircle(headCenter, headRadius, headBorder);

      // Ojos estilizados en el visor
      final eyePaint = Paint()
        ..color = theme.jointColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(headCenter.dx - headRadius * 0.35, headCenter.dy - headRadius * 0.1),
        2.5,
        eyePaint,
      );
      canvas.drawCircle(
        Offset(headCenter.dx + headRadius * 0.35, headCenter.dy - headRadius * 0.1),
        2.5,
        eyePaint,
      );
    }

    // Costados del torso
    if (ls != null && lh != null) canvas.drawLine(ls, lh, torsoPaint);
    if (rs != null && rh != null) canvas.drawLine(rs, rh, torsoPaint);
    if (lh != null && rh != null) canvas.drawLine(lh, rh, torsoPaint);
  }

  void _drawArms(Canvas canvas, double width, double height) {
    final pose = frame!.pose;
    final ls = _toOffset(pose['left_shoulder'], width, height);
    final le = _toOffset(pose['left_elbow'], width, height);
    final lw = _toOffset(pose['left_wrist'], width, height);

    final rs = _toOffset(pose['right_shoulder'], width, height);
    final re = _toOffset(pose['right_elbow'], width, height);
    final rw = _toOffset(pose['right_wrist'], width, height);

    // Brazo izquierdo
    _drawLimb(canvas, ls, le, lw, theme.leftArmColor);

    // Brazo derecho
    _drawLimb(canvas, rs, re, rw, theme.rightArmColor);
  }

  void _drawLimb(
    Canvas canvas,
    Offset? shoulder,
    Offset? elbow,
    Offset? wrist,
    Color color,
  ) {
    final bonePaint = Paint()
      ..color = color
      ..strokeWidth = theme.boneWidth
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = theme.boneWidth * 2.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = theme.glowSigma > 0
          ? ui.MaskFilter.blur(BlurStyle.normal, theme.glowSigma)
          : null;

    final jointPaint = Paint()
      ..color = theme.jointColor
      ..style = PaintingStyle.fill;

    if (shoulder != null && elbow != null) {
      if (theme.glowSigma > 0) canvas.drawLine(shoulder, elbow, glowPaint);
      canvas.drawLine(shoulder, elbow, bonePaint);
      canvas.drawCircle(elbow, theme.jointRadius, jointPaint);
    }

    if (elbow != null && wrist != null) {
      if (theme.glowSigma > 0) canvas.drawLine(elbow, wrist, glowPaint);
      canvas.drawLine(elbow, wrist, bonePaint);
      canvas.drawCircle(wrist, theme.jointRadius, jointPaint);
    }
  }

  void _drawHand(
    Canvas canvas,
    List<AvatarPoint> handPoints,
    double width,
    double height, {
    required Color boneColor,
    required bool isLeft,
  }) {
    if (handPoints.length < 21) return;

    final offsets = handPoints.map((pt) => _toOffset(pt, width, height)!).toList();

    final bonePaint = Paint()
      ..color = boneColor
      ..strokeWidth = theme.boneWidth * 0.75
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = boneColor.withValues(alpha: 0.35)
      ..strokeWidth = theme.boneWidth * 1.8
      ..strokeCap = StrokeCap.round
      ..maskFilter = theme.glowSigma > 0
          ? ui.MaskFilter.blur(BlurStyle.normal, theme.glowSigma * 0.7)
          : null;

    final jointPaint = Paint()
      ..color = theme.jointColor
      ..style = PaintingStyle.fill;

    final tipPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // 1. Dibujar falanges y segmentos óseos
    for (final conn in handConnections) {
      final p1 = offsets[conn[0]];
      final p2 = offsets[conn[1]];
      if (theme.glowSigma > 0) canvas.drawLine(p1, p2, glowPaint);
      canvas.drawLine(p1, p2, bonePaint);
    }

    // 2. Dibujar articulaciones
    for (int i = 0; i < offsets.length; i++) {
      final pt = offsets[i];
      final isTip = i == 4 || i == 8 || i == 12 || i == 16 || i == 20;
      final radius = isTip ? theme.jointRadius * 1.15 : theme.jointRadius * 0.85;

      canvas.drawCircle(pt, radius, isTip ? tipPaint : jointPaint);
    }
  }

  Offset? _toOffset(AvatarPoint? pt, double width, double height) {
    if (pt == null) return null;
    final x = isMirrored ? (1.0 - pt.x) * width : pt.x * width;
    final y = pt.y * height;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant AvatarPosePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.theme != theme ||
        oldDelegate.rightHandTrail.length != rightHandTrail.length ||
        oldDelegate.leftHandTrail.length != leftHandTrail.length;
  }
}
