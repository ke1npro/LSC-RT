import 'recorded_sign.dart';

/// Representa una toma candidata (1 de hasta 5) durante el proceso de grabación.
class SignTakeCandidate {
  final int takeNumber; // 1 a 5
  final String tempVideoPath;
  final List<SignFrameLandmarks> allFrames;
  final int videoDurationMs;
  final int trimStartFrame;
  final int trimEndFrame;

  SignTakeCandidate({
    required this.takeNumber,
    required this.tempVideoPath,
    required this.allFrames,
    required this.videoDurationMs,
    int? trimStartFrame,
    int? trimEndFrame,
  })  : trimStartFrame = (trimStartFrame ?? 0).clamp(
          0,
          allFrames.isEmpty ? 0 : allFrames.length - 1,
        ),
        trimEndFrame = (trimEndFrame ?? (allFrames.isEmpty ? 0 : allFrames.length - 1)).clamp(
          0,
          allFrames.isEmpty ? 0 : allFrames.length - 1,
        );

  int get totalRawFrames => allFrames.length;

  /// Retorna los fotogramas comprendidos estrictamente en el intervalo [trimStartFrame, trimEndFrame],
  /// con los timestamps re-indexados empezando en 0 ms.
  List<SignFrameLandmarks> get trimmedFrames {
    if (allFrames.isEmpty) return const [];
    final start = trimStartFrame.clamp(0, allFrames.length - 1);
    final end = trimEndFrame.clamp(start, allFrames.length - 1);

    final slice = allFrames.sublist(start, end + 1);
    if (slice.isEmpty) return const [];

    final baseTimeMs = slice.first.timestampMs;
    return slice.asMap().entries.map((entry) {
      final idx = entry.key;
      final original = entry.value;
      return original.copyWith(
        frameIndex: idx,
        timestampMs: original.timestampMs - baseTimeMs,
      );
    }).toList();
  }

  int get trimmedFramesCount {
    if (allFrames.isEmpty) return 0;
    final start = trimStartFrame.clamp(0, allFrames.length - 1);
    final end = trimEndFrame.clamp(start, allFrames.length - 1);
    final count = end - start + 1;
    return count < 0 ? 0 : count;
  }

  /// Conteo de frames dentro del recorte que detectan al menos [requiredHands].
  int validFramesCount(int requiredHands) {
    final frames = trimmedFrames;
    if (frames.isEmpty) return 0;
    return frames.where((f) => f.isValidFor(requiredHands)).length;
  }

  /// Porcentaje de reconocimiento de manos (0.0 a 1.0) en el rango recortado.
  double detectionRate(int requiredHands) {
    final count = trimmedFramesCount;
    if (count == 0) return 0.0;
    return validFramesCount(requiredHands) / count.toDouble();
  }

  /// Confianza promedio de MediaPipe en los frames válidos del recorte.
  double averageConfidence(int requiredHands) {
    final frames = trimmedFrames.where((f) => f.isValidFor(requiredHands)).toList();
    if (frames.isEmpty) return 0.0;
    final sum = frames.fold<double>(0.0, (acc, f) => acc + f.averageConfidence);
    return sum / frames.length;
  }

  SignTakeCandidate copyWith({
    int? takeNumber,
    String? tempVideoPath,
    List<SignFrameLandmarks>? allFrames,
    int? videoDurationMs,
    int? trimStartFrame,
    int? trimEndFrame,
  }) {
    return SignTakeCandidate(
      takeNumber: takeNumber ?? this.takeNumber,
      tempVideoPath: tempVideoPath ?? this.tempVideoPath,
      allFrames: allFrames ?? this.allFrames,
      videoDurationMs: videoDurationMs ?? this.videoDurationMs,
      trimStartFrame: trimStartFrame ?? this.trimStartFrame,
      trimEndFrame: trimEndFrame ?? this.trimEndFrame,
    );
  }
}
