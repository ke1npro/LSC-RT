import 'recorded_sign.dart';

/// Segmento temporal traducido dentro de una grabación continua de señas.
class TranslatedSignSegment {
  final String word;
  final int startFrame;
  final int endFrame;
  final int startMs;
  final int endMs;
  final double confidence; // 0.0 a 1.0

  const TranslatedSignSegment({
    required this.word,
    required this.startFrame,
    required this.endFrame,
    required this.startMs,
    required this.endMs,
    required this.confidence,
  });

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}

/// Turno de conversación en el modo Paso a Paso (Señas -> Texto o Texto -> Avatar).
class ConversationTurn {
  final String id;
  final DateTime timestamp;
  final bool isFromSigner; // true: persona sorda (señas->texto), false: respuesta (texto->avatar)
  final String text;
  final List<TranslatedSignSegment> segments;
  final List<String> matchedWords;
  final List<String> missingWords;
  final List<SignFrameLandmarks> avatarFrames;
  final List<int> wordStartFrames;

  const ConversationTurn({
    required this.id,
    required this.timestamp,
    required this.isFromSigner,
    required this.text,
    this.segments = const [],
    this.matchedWords = const [],
    this.missingWords = const [],
    this.avatarFrames = const [],
    this.wordStartFrames = const [],
  });

  bool get hasReplayableAvatar => avatarFrames.isNotEmpty;
}
