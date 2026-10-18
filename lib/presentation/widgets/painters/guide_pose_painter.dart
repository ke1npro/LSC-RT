import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/arm_skeleton.dart';
import '../../../domain/entities/body_pose.dart';
import '../../../domain/entities/hand_pose.dart';

class GuidePosePainter extends CustomPainter {
  final BodyPose? guidePose;
  final double matchScore;

  static const List<List<int>> _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // Pulgar
    [0, 5], [5, 6], [6, 7], [7, 8], // Índice
    [5, 9], [9, 10], [10, 11], [11, 12], // Medio
    [9, 13], [13, 14], [14, 15], [15, 16], // Anular
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // Meñique
  ];

  GuidePosePainter({
    required this.guidePose,
    required this.matchScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (guidePose == null) return;

    final center = Offset(size.width * 0.5, size.height * 0.45);
    final scale = size.width / 400.0;

    // Interpolar color entre Morado Tutor y Verde Menta según matchScore
    final effectiveColor = Color.lerp(
      AppColors.guideViolet,
      AppColors.mintGreen,
      matchScore.clamp(0.0, 1.0),
    )!;

    final bonePaint = Paint()
      ..color = effectiveColor.withValues(alpha: 0.85)
      ..strokeWidth = 3.5 * scale
      ..strokeCap = StrokeCap.round;

    final armPaint = Paint()
      ..color = effectiveColor.withValues(alpha: 0.75)
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round;

    final claviclePaint = Paint()
      ..color = effectiveColor.withValues(alpha: 0.40)
      ..strokeWidth = 2.5 * scale
      ..strokeCap = StrokeCap.round;

    final jointFill = Paint()
      ..color = effectiveColor
      ..style = PaintingStyle.fill;

    final jointStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.8 * scale
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = effectiveColor.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // 1. Dibujar Brazo Guía
    for (final arm in guidePose!.arms) {
      _drawGuideArm(
        canvas,
        arm,
        scale,
        armPaint,
        claviclePaint,
        jointFill,
        jointStroke,
        glowPaint,
      );
    }

    // 2. Dibujar Mano Guía
    for (final hand in guidePose!.hands) {
      _drawGuideHand(
        canvas,
        hand,
        scale,
        bonePaint,
        jointFill,
        jointStroke,
        glowPaint,
      );
    }

    canvas.restore();
  }

  void _drawGuideArm(
    Canvas canvas,
    ArmSkeleton arm,
    double scale,
    Paint armPaint,
    Paint claviclePaint,
    Paint jointFill,
    Paint jointStroke,
    Paint glowPaint,
  ) {
    final sternum = Offset(arm.sternum.x, arm.sternum.y);
    final shoulder = Offset(arm.shoulder.x, arm.shoulder.y);
    final elbow = Offset(arm.elbow.x, arm.elbow.y);
    final wrist = Offset(arm.wrist.x, arm.wrist.y);

    // Glow
    canvas.drawLine(shoulder, elbow, glowPaint);
    canvas.drawLine(elbow, wrist, glowPaint);

    // Clavícula
    canvas.drawLine(shoulder, sternum, claviclePaint);
    // Húmero
    canvas.drawLine(shoulder, elbow, armPaint);
    // Antebrazo
    canvas.drawLine(elbow, wrist, armPaint);

    // Articulaciones
    canvas.drawCircle(shoulder, 8.0 * scale, jointFill);
    canvas.drawCircle(shoulder, 8.0 * scale, jointStroke);

    canvas.drawCircle(elbow, 7.0 * scale, jointFill);
    canvas.drawCircle(elbow, 7.0 * scale, jointStroke);
  }

  void _drawGuideHand(
    Canvas canvas,
    HandPose hand,
    double scale,
    Paint bonePaint,
    Paint jointFill,
    Paint jointStroke,
    Paint glowPaint,
  ) {
    final offsets = hand.landmarks.map((lm) => Offset(lm.x, lm.y)).toList();

    // Huesos de los dedos
    for (final conn in _connections) {
      if (conn[0] < offsets.length && conn[1] < offsets.length) {
        canvas.drawLine(offsets[conn[0]], offsets[conn[1]], glowPaint);
        canvas.drawLine(offsets[conn[0]], offsets[conn[1]], bonePaint);
      }
    }

    // Nodos
    for (int i = 0; i < offsets.length; i++) {
      final isTip = i == 4 || i == 8 || i == 12 || i == 16 || i == 20;
      final radius = (isTip ? 5.5 : 3.5) * scale;

      canvas.drawCircle(offsets[i], radius, jointFill);
      canvas.drawCircle(offsets[i], radius, jointStroke);
    }
  }

  @override
  bool shouldRepaint(covariant GuidePosePainter oldDelegate) {
    return oldDelegate.guidePose != guidePose ||
        oldDelegate.matchScore != matchScore;
  }
}
