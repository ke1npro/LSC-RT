import 'hand_pose.dart';

/// Representa los landmarks de manos capturados en un fotograma específico.
class SignFrameLandmarks {
  final int frameIndex;
  final int timestampMs;
  final List<HandPose> hands;

  const SignFrameLandmarks({
    required this.frameIndex,
    required this.timestampMs,
    required this.hands,
  });

  /// Evalúa si el frame posee al menos la cantidad de manos válidas requeridas.
  bool isValidFor(int requiredHands) {
    final validHands = hands.where((h) => h.isValid).length;
    return validHands >= requiredHands;
  }

  /// Retorna la confianza promedio de las manos válidas en este fotograma.
  double get averageConfidence {
    final validHands = hands.where((h) => h.isValid).toList();
    if (validHands.isEmpty) return 0.0;
    final sum = validHands.fold<double>(0.0, (acc, h) => acc + h.confidence);
    return sum / validHands.length;
  }

  SignFrameLandmarks copyWith({
    int? frameIndex,
    int? timestampMs,
    List<HandPose>? hands,
  }) {
    return SignFrameLandmarks(
      frameIndex: frameIndex ?? this.frameIndex,
      timestampMs: timestampMs ?? this.timestampMs,
      hands: hands ?? this.hands,
    );
  }

  Map<String, dynamic> toJson() => {
        'frameIndex': frameIndex,
        'timestampMs': timestampMs,
        'hands': hands.map((h) => h.toJson()).toList(),
      };

  factory SignFrameLandmarks.fromJson(Map<String, dynamic> json) {
    final handsList = (json['hands'] as List<dynamic>?)
            ?.map((e) => HandPose.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SignFrameLandmarks(
      frameIndex: (json['frameIndex'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      hands: handsList,
    );
  }
}

/// Representa una seña registrada y curada por el usuario en el diccionario.
class RecordedSign {
  final String id;
  final String word;
  final String category;
  final int requiredHands; // 1 o 2
  final double fps;
  final double detectionRate; // 0.0 a 1.0
  final double averageConfidence; // 0.0 a 1.0
  final int totalTakesEvaluated; // 1 a 5
  final DateTime createdAt;
  final List<SignFrameLandmarks> frames;

  const RecordedSign({
    required this.id,
    required this.word,
    required this.category,
    required this.requiredHands,
    required this.fps,
    required this.detectionRate,
    required this.averageConfidence,
    required this.totalTakesEvaluated,
    required this.createdAt,
    required this.frames,
  });

  int get frameCount => frames.length;

  int get durationMs {
    if (frames.isEmpty) return 0;
    return frames.last.timestampMs - frames.first.timestampMs;
  }

  bool get isBimanual => requiredHands >= 2;

  RecordedSign copyWith({
    String? id,
    String? word,
    String? category,
    int? requiredHands,
    double? fps,
    double? detectionRate,
    double? averageConfidence,
    int? totalTakesEvaluated,
    DateTime? createdAt,
    List<SignFrameLandmarks>? frames,
  }) {
    return RecordedSign(
      id: id ?? this.id,
      word: word ?? this.word,
      category: category ?? this.category,
      requiredHands: requiredHands ?? this.requiredHands,
      fps: fps ?? this.fps,
      detectionRate: detectionRate ?? this.detectionRate,
      averageConfidence: averageConfidence ?? this.averageConfidence,
      totalTakesEvaluated: totalTakesEvaluated ?? this.totalTakesEvaluated,
      createdAt: createdAt ?? this.createdAt,
      frames: frames ?? this.frames,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'category': category,
        'requiredHands': requiredHands,
        'fps': fps,
        'detectionRate': detectionRate,
        'averageConfidence': averageConfidence,
        'totalTakesEvaluated': totalTakesEvaluated,
        'createdAt': createdAt.toIso8601String(),
        'frames': frames.map((f) => f.toJson()).toList(),
      };

  factory RecordedSign.fromJson(Map<String, dynamic> json) {
    final rawFrames = (json['frames'] as List<dynamic>?)
            ?.map((e) => SignFrameLandmarks.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return RecordedSign(
      id: json['id'] as String? ?? '',
      word: (json['word'] as String? ?? '').toUpperCase().trim(),
      category: json['category'] as String? ?? 'General',
      requiredHands: (json['requiredHands'] as num?)?.toInt() ?? 1,
      fps: (json['fps'] as num?)?.toDouble() ?? 30.0,
      detectionRate: (json['detectionRate'] as num?)?.toDouble() ?? 0.0,
      averageConfidence: (json['averageConfidence'] as num?)?.toDouble() ?? 0.0,
      totalTakesEvaluated: (json['totalTakesEvaluated'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      frames: rawFrames,
    );
  }
}
