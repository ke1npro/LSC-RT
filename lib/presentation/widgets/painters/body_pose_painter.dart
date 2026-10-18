import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/arm_skeleton.dart';
import '../../../domain/entities/body_pose.dart';
import '../../../domain/entities/face_bounds.dart';
import '../../../domain/entities/hand_pose.dart';

class BodyPosePainter extends CustomPainter {
  final BodyPose? pose;
  final bool showOverlay;
  final bool showFace;
  final bool isMirrored;

  static const List<List<int>> _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // Pulgar
    [0, 5], [5, 6], [6, 7], [7, 8], // Índice
    [5, 9], [9, 10], [10, 11], [11, 12], // Medio
    [9, 13], [13, 14], [14, 15], [15, 16], // Anular
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // Meñique
  ];

  BodyPosePainter({
    required this.pose,
    this.showOverlay = true,
    this.showFace = true,
    this.isMirrored = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showOverlay || pose == null) return;

    final currentPose = pose!;
    if (currentPose.hands.isEmpty && currentPose.primaryFace == null) return;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    if (isMirrored) {
      canvas.scale(-1, 1);
    }

    // 1. Visor facial sutil de 4 esquinas (High-tech bracket viewfinder)
    if (showFace && currentPose.primaryFace != null) {
      _drawFaceCorners(canvas, currentPose.primaryFace!, size);
    }

    // 2. Renderizado del Brazo Completo Anatómico (Two-Bone IK ya resuelto)
    for (final arm in currentPose.arms) {
      _drawArm(canvas, arm);
    }

    // 3. Renderizado de la Mano (21 Landmarks + Huesos finos)
    for (final hand in currentPose.hands) {
      _drawHand(canvas, hand, size);
    }

    canvas.restore();
  }

  void _drawFaceCorners(Canvas canvas, FaceBounds face, Size size) {
    final cx = (face.centerX - 0.5) * size.width;
    final cy = (face.centerY - 0.5) * size.height;
    final w = face.width * size.width;
    final h = face.height * size.height;

    final left = cx - w / 2;
    final top = cy - h / 2;
    final right = cx + w / 2;
    final bottom = cy + h / 2;
    final cornerLen = math.min(w, h) * 0.18;

    final paint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.85)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Esquina superior izquierda
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLen), paint);

    // Esquina superior derecha
    canvas.drawLine(Offset(right, top), Offset(right - cornerLen, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLen), paint);

    // Esquina inferior izquierda
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLen, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLen), paint);

    // Esquina inferior derecha
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLen, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLen), paint);
  }

  void _drawArm(Canvas canvas, ArmSkeleton arm) {
    final bonePaint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final claviclePaint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final jointFill = Paint()
      ..color = AppColors.cyanAccent
      ..style = PaintingStyle.fill;

    final jointHalo = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    final jointStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final sternum = Offset(arm.sternum.x, arm.sternum.y);
    final shoulder = Offset(arm.shoulder.x, arm.shoulder.y);
    final elbow = Offset(arm.elbow.x, arm.elbow.y);
    final wrist = Offset(arm.wrist.x, arm.wrist.y);

    // Línea de clavícula
    canvas.drawLine(shoulder, sternum, claviclePaint);
    // Húmero (Hombro -> Codo)
    canvas.drawLine(shoulder, elbow, bonePaint);
    // Antebrazo (Codo -> Muñeca)
    canvas.drawLine(elbow, wrist, bonePaint);

    // Articulación del Hombro
    canvas.drawCircle(shoulder, 8.0, jointHalo);
    canvas.drawCircle(shoulder, 5.0, jointFill);
    canvas.drawCircle(shoulder, 5.0, jointStroke);

    // Articulación del Codo
    canvas.drawCircle(elbow, 7.0, jointHalo);
    canvas.drawCircle(elbow, 4.5, jointFill);
    canvas.drawCircle(elbow, 4.5, jointStroke);
  }

  void _drawHand(Canvas canvas, HandPose hand, Size size) {
    final bonePaint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.9)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final jointFill = Paint()
      ..color = AppColors.cyanAccent
      ..style = PaintingStyle.fill;

    final jointStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Convertir landmarks a coordenadas centradas
    final offsets = hand.landmarks.map((lm) {
      final dx = (lm.x - 0.5) * size.width;
      final dy = (lm.y - 0.5) * size.height;
      return Offset(dx, dy);
    }).toList();

    // Dibujar conexiones óseas de los dedos
    for (final conn in _connections) {
      if (conn[0] < offsets.length && conn[1] < offsets.length) {
        canvas.drawLine(offsets[conn[0]], offsets[conn[1]], bonePaint);
      }
    }

    // Dibujar nodos de las articulaciones
    for (int i = 0; i < offsets.length; i++) {
      final isTip = i == 4 || i == 8 || i == 12 || i == 16 || i == 20;
      final radius = isTip ? 4.5 : 3.0;

      canvas.drawCircle(offsets[i], radius, jointFill);
      canvas.drawCircle(offsets[i], radius, jointStroke);
    }
  }

  @override
  bool shouldRepaint(covariant BodyPosePainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showFace != showFace ||
        oldDelegate.isMirrored != isMirrored;
  }
}
