import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/theme/avatar_theme.dart';
import '../../../domain/entities/avatar_sign_data.dart';

/// Painter del Avatar ilustrado de Lengua de Señas.
///
/// Dibuja un personaje con volumen (cabeza, cabello, cuello, torso con ropa,
/// brazos con mangas y manos de piel con silueta) a partir de los mismos
/// landmarks del banco de movimiento. Toda la estética se lee desde
/// [AvatarTheme], de modo que cambiar paleta o estilo no toca la cinemática.
///
/// El encuadre es automático: el personaje se centra y escala usando los
/// hombros de cada cuadro, por lo que siempre ocupa el lienzo sin importar
/// dónde estaba la persona en el video original.
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

  // Cadenas de dedos (índices MediaPipe), de atrás hacia adelante.
  static const List<List<int>> _fingerChains = [
    [17, 18, 19, 20], // Meñique
    [13, 14, 15, 16], // Anular
    [9, 10, 11, 12], // Medio
    [5, 6, 7, 8], // Índice
    [1, 2, 3, 4], // Pulgar (se dibuja al final)
  ];
  static const List<int> _palmIdx = [0, 1, 5, 9, 13, 17];

  /// Conexiones de los 21 puntos de la mano (se conserva por compatibilidad).
  static const List<List<int>> handConnections = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [9, 10], [10, 11], [11, 12],
    [13, 14], [14, 15], [15, 16],
    [0, 17], [17, 18], [18, 19], [19, 20],
    [5, 9], [9, 13], [13, 17],
  ];

  // Estado del encuadre calculado en cada paint.
  late Offset _anchorRaw;
  late Offset _anchorScreen;
  late double _k;
  late double _s; // Unidad corporal: ancho de hombros en pixeles.

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || size.isEmpty) return;

    _setupCamera(f, size);
    final ow = math.max(1.2, _s * 0.018 * theme.outlineScale);

    if (theme.showBackdrop) _drawBackdrop(canvas, size);

    final ls = _map(f.pose['left_shoulder']);
    final rs = _map(f.pose['right_shoulder']);
    final shoulderL = ls ?? _anchorScreen + Offset(_s / 2, 0);
    final shoulderR = rs ?? _anchorScreen - Offset(_s / 2, 0);

    // Ejes locales del torso.
    var dir = shoulderL - shoulderR;
    final len = dir.distance;
    dir = len > 0 ? dir / len : const Offset(1, 0);
    var down = Offset(-dir.dy, dir.dx);
    if (down.dy < 0) down = -down;
    final mid = (shoulderL + shoulderR) / 2;

    // La dirección de la cabeza sale de los datos (inclinaciones), pero la
    // longitud del cuello se fija para mantener proporciones de personaje.
    final nose = _map(f.pose['nose']);
    var headVec = nose != null ? nose - mid : -down;
    if (headVec.distance < 1e-3) headVec = -down;
    final headCenter = mid + headVec / headVec.distance * (_s * 0.56);

    _drawNeck(canvas, mid, headCenter, ow);
    _drawTorso(canvas, shoulderL, shoulderR, mid, dir, down, ow);
    _drawHead(canvas, headCenter, mid, ow);

    // Puntos finales de cada brazo (se unen a la muñeca de la mano si existe).
    final lHand = _handOffsets(f.hasLeftHand ? f.leftHand : null);
    final rHand = _handOffsets(f.hasRightHand ? f.rightHand : null);
    final lEnd = lHand?.first ?? _map(f.pose['left_wrist']);
    final rEnd = rHand?.first ?? _map(f.pose['right_wrist']);

    // El brazo más lejano (z mayor) se dibuja primero.
    final lz = f.pose['left_wrist']?.z ?? 0;
    final rz = f.pose['right_wrist']?.z ?? 0;
    final arms = <_ArmSpec>[
      _ArmSpec(shoulderL, _map(f.pose['left_elbow']), lEnd, lHand,
          theme.leftHandColor, lz, leftHandTrail),
      _ArmSpec(shoulderR, _map(f.pose['right_elbow']), rEnd, rHand,
          theme.rightHandColor, rz, rightHandTrail),
    ]..sort((a, b) => b.z.compareTo(a.z));

    for (final arm in arms) {
      if (theme.showTrail) _drawTrail(canvas, arm.trail, arm.color);
      _drawArm(canvas, arm.shoulder, arm.elbow, arm.end, ow);
      if (arm.hand != null) _drawHand(canvas, arm.hand!, arm.color, ow);
    }
  }

  // ---------------------------------------------------------------------------
  // Encuadre
  // ---------------------------------------------------------------------------

  Offset _raw(double x, double y) =>
      Offset((isMirrored ? 1.0 - x : x) * theme.sourceAspect, y);

  void _setupCamera(AvatarFrame f, Size size) {
    final ls = f.pose['left_shoulder'];
    final rs = f.pose['right_shoulder'];
    double sRaw;
    if (ls != null && rs != null) {
      final a = _raw(ls.x, ls.y);
      final b = _raw(rs.x, rs.y);
      _anchorRaw = (a + b) / 2;
      sRaw = math.max((a - b).distance, 1e-3);
    } else {
      _anchorRaw = _raw(0.5, 0.45);
      sRaw = 0.18;
    }
    _s = math.min(size.width * 0.36, size.height * 0.30);
    _k = _s / sRaw;
    _anchorScreen = Offset(size.width / 2, size.height * 0.50);
  }

  Offset? _map(AvatarPoint? p) {
    if (p == null) return null;
    return _anchorScreen + (_raw(p.x, p.y) - _anchorRaw) * _k;
  }

  List<Offset>? _handOffsets(List<AvatarPoint>? pts) {
    if (pts == null || pts.length < 21) return null;
    return pts.map((p) => _map(p)!).toList();
  }

  // ---------------------------------------------------------------------------
  // Fondo
  // ---------------------------------------------------------------------------

  void _drawBackdrop(Canvas canvas, Size size) {
    final center = _anchorScreen - Offset(0, _s * 0.25);
    final r = _s * 1.9;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          theme.backdropColor.withValues(alpha: 0.55),
          theme.backdropColor.withValues(alpha: 0.0),
        ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Cuerpo
  // ---------------------------------------------------------------------------

  void _drawNeck(Canvas canvas, Offset mid, Offset head, double ow) {
    final w = _s * 0.24;
    final top = head + (mid - head) * 0.35;
    final paintOutline = Paint()
      ..color = theme.outlineColor
      ..strokeWidth = w + ow * 2
      ..strokeCap = StrokeCap.round;
    final paintFill = Paint()
      ..color = theme.skinShadeColor
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(top, mid, paintOutline);
    canvas.drawLine(top, mid, paintFill);
  }

  void _drawTorso(Canvas canvas, Offset ls, Offset rs, Offset mid, Offset dir,
      Offset down, double ow) {
    final s = _s;
    final lt = ls + dir * (s * 0.08);
    final rt = rs - dir * (s * 0.08);
    final waist = mid + down * (s * 1.7);
    final neckL = mid + dir * (s * 0.17) - down * (s * 0.03);
    final neckR = mid - dir * (s * 0.17) - down * (s * 0.03);

    final path = Path()
      ..moveTo(neckL.dx, neckL.dy);
    final c1 = ls - down * (s * 0.07);
    final e1 = lt + down * (s * 0.14);
    path.quadraticBezierTo(c1.dx, c1.dy, e1.dx, e1.dy);
    final wl = waist + dir * (s * 0.46);
    final wr = waist - dir * (s * 0.46);
    path.lineTo(wl.dx, wl.dy);
    path.lineTo(wr.dx, wr.dy);
    final e2 = rt + down * (s * 0.14);
    path.lineTo(e2.dx, e2.dy);
    final c2 = rs - down * (s * 0.07);
    path.quadraticBezierTo(c2.dx, c2.dy, neckR.dx, neckR.dy);
    final collar = mid + down * (s * 0.16);
    path.quadraticBezierTo(collar.dx, collar.dy, neckL.dx, neckL.dy);
    path.close();

    final shade = Paint()
      ..shader = ui.Gradient.linear(
        mid - down * (s * 0.1),
        waist,
        [theme.shirtColor, theme.shirtShadeColor],
      );
    canvas.drawPath(path, shade);
    canvas.drawPath(
      path,
      Paint()
        ..color = theme.outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ow
        ..strokeJoin = StrokeJoin.round,
    );

    // Brillo suave en el pecho para dar volumen.
    final shine = mid + down * (s * 0.45) + dir * (s * 0.12);
    canvas.drawCircle(
      shine,
      s * 0.35,
      Paint()
        ..shader = ui.Gradient.radial(shine, s * 0.35, [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
        ]),
    );
  }

  void _drawHead(Canvas canvas, Offset c, Offset mid, double ow) {
    final s = _s;
    final w = s * 0.56;
    final h = s * 0.68;

    // Inclinación de la cabeza según el vector cuello->cabeza.
    final v = c - mid;
    final tilt = math.atan2(v.dx, -v.dy).clamp(-0.5, 0.5);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);

    final outline = Paint()
      ..color = theme.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ow;

    // Cabello trasero (volumen detrás de la cabeza).
    final hairBack = Rect.fromCenter(
        center: Offset(0, -h * 0.06), width: w * 1.12, height: h * 1.02);
    canvas.drawOval(hairBack, Paint()..color = theme.hairColor);
    canvas.drawOval(hairBack, outline);

    // Orejas.
    for (final sx in [-1.0, 1.0]) {
      final ear = Rect.fromCenter(
          center: Offset(sx * w * 0.5, h * 0.04),
          width: w * 0.16,
          height: h * 0.22);
      canvas.drawOval(ear, Paint()..color = theme.skinShadeColor);
      canvas.drawOval(ear, outline);
    }

    // Rostro.
    final face =
        Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawOval(
      face,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-w * 0.12, -h * 0.12),
          w * 0.8,
          [theme.skinColor, theme.skinShadeColor],
        ),
    );

    // Flequillo ilustrado sin canvas.clipPath (evita capas intermedias en GPU)
    final fringe = Path()
      ..moveTo(-w * 0.48, -h * 0.10)
      ..quadraticBezierTo(0, -h * 0.58, w * 0.48, -h * 0.12)
      ..quadraticBezierTo(w * 0.25, -h * 0.30, w * 0.05, -h * 0.20)
      ..quadraticBezierTo(-w * 0.25, -h * 0.34, -w * 0.48, -h * 0.10)
      ..close();
    canvas.drawPath(fringe, Paint()..color = theme.hairColor);
    canvas.drawOval(face, outline);

    // Ojos con parpadeo periódico.
    final ms = DateTime.now().millisecondsSinceEpoch % 4200;
    final blink = ms < 130 ? 0.12 : 1.0;
    final eyeR = w * 0.065;
    for (final sx in [-1.0, 1.0]) {
      final ec = Offset(sx * w * 0.2, h * 0.03);
      canvas.drawOval(
        Rect.fromCenter(
            center: ec, width: eyeR * 2, height: eyeR * 2.3 * blink),
        Paint()..color = theme.outlineColor,
      );
      if (blink > 0.5) {
        canvas.drawCircle(ec + Offset(eyeR * 0.35, -eyeR * 0.45),
            eyeR * 0.35, Paint()..color = Colors.white);
      }
      // Ceja.
      final brow = Path()
        ..moveTo(ec.dx - eyeR * 1.4, ec.dy - eyeR * 2.0)
        ..quadraticBezierTo(ec.dx, ec.dy - eyeR * 2.9, ec.dx + eyeR * 1.4,
            ec.dy - eyeR * 2.1);
      canvas.drawPath(
        brow,
        Paint()
          ..color = theme.hairColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = ow * 1.4
          ..strokeCap = StrokeCap.round,
      );
      // Mejilla.
      canvas.drawCircle(
        Offset(sx * w * 0.28, h * 0.18),
        w * 0.08,
        Paint()..color = const Color(0xFFFF7A7A).withValues(alpha: 0.22),
      );
    }

    // Sonrisa.
    final mouth = Path()
      ..moveTo(-w * 0.1, h * 0.2)
      ..quadraticBezierTo(0, h * 0.28, w * 0.1, h * 0.2);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = theme.outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ow * 1.3
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  void _drawArm(
      Canvas canvas, Offset shoulder, Offset? elbow, Offset? end, double ow) {
    if (elbow == null) return;
    final upperW = _s * 0.2;
    final foreW = _s * 0.16;

    void seg(Offset a, Offset b, double w, Color c) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = theme.outlineColor
          ..strokeWidth = w + ow * 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = c
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    seg(shoulder, elbow, upperW, theme.shirtColor);
    if (end != null) {
      // La manga termina en un puño antes de la muñeca.
      final cuff = elbow + (end - elbow) * 0.82;
      seg(elbow, cuff, foreW, theme.shirtShadeColor);
      // Re-pinta el codo para unir ambos segmentos sin costura.
      canvas.drawCircle(elbow, upperW * 0.5, Paint()..color = theme.shirtColor);
      seg(cuff, end, foreW * 0.72, theme.skinShadeColor);
    }
  }

  // ---------------------------------------------------------------------------
  // Manos
  // ---------------------------------------------------------------------------

  void _drawHand(Canvas canvas, List<Offset> p, Color identity, double ow) {
    final palmLen = (p[0] - p[9]).distance;
    final fw = (palmLen * 0.32).clamp(_s * 0.025, _s * 0.075);
    final palmCenter = (p[0] + p[5] + p[17]) / 3;

    // Halo de identidad (izquierda / derecha) acelerado por GPU vía gradiente radial nativo.
    if (theme.glowSigma > 0) {
      final glowRadius = math.max(palmLen * 1.5, _s * 0.18);
      canvas.drawCircle(
        palmCenter,
        glowRadius,
        Paint()
          ..shader = ui.Gradient.radial(
            palmCenter,
            glowRadius,
            [
              identity.withValues(alpha: 0.32),
              identity.withValues(alpha: 0.0),
            ],
          ),
      );
    }

    // Palma: polígono relleno + trazo grueso para redondear bordes.
    final palm = Path()..moveTo(p[_palmIdx[0]].dx, p[_palmIdx[0]].dy);
    for (final i in _palmIdx.skip(1)) {
      palm.lineTo(p[i].dx, p[i].dy);
    }
    palm.close();
    canvas.drawPath(
      palm,
      Paint()
        ..color = theme.outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = fw * 1.2 + ow * 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      palm,
      Paint()
        ..color = theme.skinColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = fw * 1.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(palm, Paint()..color = theme.skinColor);

    // Dedos: cada uno con su propio contorno para que se distingan aunque
    // se superpongan con la palma.
    for (final chain in _fingerChains) {
      final path = Path()..moveTo(p[chain[0]].dx, p[chain[0]].dy);
      for (final i in chain.skip(1)) {
        path.lineTo(p[i].dx, p[i].dy);
      }
      final isThumb = chain.first == 1;
      final w = isThumb ? fw * 1.08 : fw;
      canvas.drawPath(
        path,
        Paint()
          ..color = theme.outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = w + ow * 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = theme.skinColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Uña con el color de identidad para seguir la punta con la vista.
      canvas.drawCircle(
        p[chain.last],
        w * 0.28,
        Paint()..color = Color.lerp(theme.skinColor, identity, 0.55)!,
      );
    }
  }

  void _drawTrail(Canvas canvas, List<Offset> trail, Color color) {
    if (trail.length < 2) return;
    final pts = trail.map((o) => _map(AvatarPoint(o.dx, o.dy))!).toList();
    for (int i = 0; i < pts.length - 1; i++) {
      final t = (i + 1) / pts.length;
      canvas.drawLine(
        pts[i],
        pts[i + 1],
        Paint()
          ..color = color.withValues(alpha: t * 0.5)
          ..strokeWidth = _s * 0.07 * t
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AvatarPosePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.theme != theme ||
        oldDelegate.isMirrored != isMirrored ||
        oldDelegate.rightHandTrail.length != rightHandTrail.length ||
        oldDelegate.leftHandTrail.length != leftHandTrail.length;
  }
}

class _ArmSpec {
  final Offset shoulder;
  final Offset? elbow;
  final Offset? end;
  final List<Offset>? hand;
  final Color color;
  final double z;
  final List<Offset> trail;

  _ArmSpec(this.shoulder, this.elbow, this.end, this.hand, this.color, this.z,
      this.trail);
}
