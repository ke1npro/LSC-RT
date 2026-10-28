import 'dart:convert';
import 'package:flutter/services.dart';
import '../../domain/entities/avatar_sign_data.dart';

class AvatarMotionDataSource {
  final Map<String, AvatarSignData> _signs = {};
  List<AvatarSignData> _allSignsList = [];
  List<String> _cachedCategories = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  List<AvatarSignData> get allSigns => _allSignsList;

  Future<void> initialize() async {
    if (_isLoaded) return;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/lsc_avatar_motion_bank.json');
      if (jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        final uniqueSigns = <String, AvatarSignData>{};
        final uniqueCats = <String>{};

        decoded.forEach((key, val) {
          final sign = AvatarSignData.fromJson(val as Map<String, dynamic>);
          _signs[key.toLowerCase()] = sign;
          _signs[_cleanKey(sign.displayName)] = sign;
          uniqueSigns[sign.id] = sign;
          uniqueCats.add(sign.category);
        });

        _allSignsList = uniqueSigns.values.toList();
        _cachedCategories = uniqueCats.toList()..sort();
        _isLoaded = true;
      }
    } catch (e) {
      // Manejo silencioso con fallback
      _isLoaded = false;
    }
  }

  AvatarSignData? getSign(String query) {
    final clean = _cleanKey(query);
    return _signs[clean];
  }

  List<AvatarSignData> searchSigns(String query) {
    if (query.trim().isEmpty) return _allSignsList;
    final q = _cleanKey(query);
    return _allSignsList.where((s) {
      return _cleanKey(s.displayName).contains(q) ||
          _cleanKey(s.category).contains(q);
    }).toList();
  }

  List<String> getCategories() => _cachedCategories;

  /// Concatena una secuencia de señas con transición cinemática suave (Cubic Hermite Blending)
  List<AvatarFrame> synthesizeSentence(List<AvatarSignData> sequence) {
    if (sequence.isEmpty) return [];
    if (sequence.length == 1) return sequence.first.frames;

    final result = <AvatarFrame>[];
    for (int i = 0; i < sequence.length; i++) {
      final currentSign = sequence[i];
      result.addAll(currentSign.frames);

      // Si hay una seña siguiente, insertar 8 cuadros de transición suave
      if (i < sequence.length - 1) {
        final nextSign = sequence[i + 1];
        if (currentSign.frames.isNotEmpty && nextSign.frames.isNotEmpty) {
          final lastFrame = currentSign.frames.last;
          final firstFrame = nextSign.frames.first;
          final transition = _blendFrames(lastFrame, firstFrame, 8);
          result.addAll(transition);
        }
      }
    }
    return result;
  }

  List<AvatarFrame> _blendFrames(
      AvatarFrame f1, AvatarFrame f2, int steps) {
    final blended = <AvatarFrame>[];
    for (int s = 1; s <= steps; s++) {
      final t = s / (steps + 1);
      // Hermite smoothstep: 3t^2 - 2t^3
      final smoothT = t * t * (3.0 - 2.0 * t);

      // Interpolar pose
      final poseInterp = <String, AvatarPoint>{};
      f1.pose.forEach((k, p1) {
        final p2 = f2.pose[k] ?? p1;
        poseInterp[k] = AvatarPoint(
          p1.x + (p2.x - p1.x) * smoothT,
          p1.y + (p2.y - p1.y) * smoothT,
          p1.z + (p2.z - p1.z) * smoothT,
        );
      });

      // Interpolar manos si existen en ambos
      List<AvatarPoint>? lh;
      if (f1.leftHand != null && f2.leftHand != null) {
        lh = [];
        for (int p = 0; p < 21; p++) {
          final pt1 = f1.leftHand![p];
          final pt2 = f2.leftHand![p];
          lh.add(AvatarPoint(
            pt1.x + (pt2.x - pt1.x) * smoothT,
            pt1.y + (pt2.y - pt1.y) * smoothT,
            pt1.z + (pt2.z - pt1.z) * smoothT,
          ));
        }
      } else {
        lh = f1.leftHand ?? f2.leftHand;
      }

      List<AvatarPoint>? rh;
      if (f1.rightHand != null && f2.rightHand != null) {
        rh = [];
        for (int p = 0; p < 21; p++) {
          final pt1 = f1.rightHand![p];
          final pt2 = f2.rightHand![p];
          rh.add(AvatarPoint(
            pt1.x + (pt2.x - pt1.x) * smoothT,
            pt1.y + (pt2.y - pt1.y) * smoothT,
            pt1.z + (pt2.z - pt1.z) * smoothT,
          ));
        }
      } else {
        rh = f1.rightHand ?? f2.rightHand;
      }

      blended.add(AvatarFrame(
        pose: poseInterp,
        leftHand: lh,
        rightHand: rh,
        hasLeftHand: lh != null,
        hasRightHand: rh != null,
      ));
    }
    return blended;
  }

  String _cleanKey(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('¿', '')
        .replaceAll('?', '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }
}
