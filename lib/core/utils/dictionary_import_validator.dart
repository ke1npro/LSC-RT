import 'dart:math' as math;

/// Validacion defensiva (M4) de diccionarios importados desde JSON no confiable.
/// Rechaza estructuras sobredimensionadas, tipos inesperados, NaN/Infinity y rangos imposibles.
class DictionaryImportValidator {
  DictionaryImportValidator._();

  static const int maxImportChars = 50 * 1024 * 1024;
  static const int maxSigns = 1000;
  static const int maxFramesPerSign = 400;
  static const int maxHandsPerFrame = 2;
  static const int landmarksPerHand = 21;
  static const double coordLimit = 5.0;
  static final RegExp _idPattern = RegExp(r'^[a-zA-Z0-9_\-]{1,96}$');

  /// Devuelve true si el mapa de una seña es estructuralmente seguro de parsear.
  static bool isValidSignJson(dynamic raw) {
    if (raw is! Map) return false;

    final id = raw['id'];
    if (id is! String || !_idPattern.hasMatch(id)) return false;
    if (raw['word'] is! String) return false;

    final hands = raw['requiredHands'];
    if (hands is! num || (hands != 1 && hands != 2)) return false;

    final fps = raw['fps'];
    if (fps != null && (fps is! num || !_finiteIn(fps, 1, 120))) return false;

    final frames = raw['frames'];
    if (frames is! List || frames.isEmpty || frames.length > maxFramesPerSign) {
      return false;
    }

    for (final frame in frames) {
      if (frame is! Map) return false;
      final handList = frame['hands'];
      if (handList is! List || handList.length > maxHandsPerFrame) return false;
      for (final hand in handList) {
        if (!_isValidHand(hand)) return false;
      }
    }
    return true;
  }

  static bool _isValidHand(dynamic hand) {
    if (hand is! Map) return false;
    final conf = hand['confidence'];
    if (conf != null && (conf is! num || !_finiteIn(conf, 0, 1))) return false;
    final points = hand['landmarks'];
    if (points is! List || points.length != landmarksPerHand) return false;
    for (final p in points) {
      if (p is! Map) return false;
      for (final axis in const ['x', 'y', 'z']) {
        final v = p[axis];
        if (v is! num || !_finiteIn(v, -coordLimit, coordLimit)) return false;
      }
    }
    return true;
  }

  static bool _finiteIn(num v, double min, double max) {
    final d = v.toDouble();
    return !d.isNaN && !d.isInfinite && d >= math.min(min, max) && d <= max;
  }
}
