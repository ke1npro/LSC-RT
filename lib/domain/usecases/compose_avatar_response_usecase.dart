import 'dart:math' as math;
import '../entities/hand_pose.dart';
import '../entities/landmark_point.dart';
import '../entities/recorded_sign.dart';

class ComposedAvatarResponse {
  final String originalText;
  final List<RecordedSign> matchedSigns;
  final List<String> missingWords;
  final List<SignFrameLandmarks> frames;
  final List<int> wordStartFrames;

  const ComposedAvatarResponse({
    required this.originalText,
    required this.matchedSigns,
    required this.missingWords,
    required this.frames,
    required this.wordStartFrames,
  });

  bool get hasAnimation => frames.isNotEmpty;
}

/// Convierte un texto escrito en una secuencia animada de landmarks tomada del
/// diccionario del usuario mediante **búsqueda greedy por coincidencia más larga**,
/// suavizando las transiciones entre señas con interpolación Hermite.
class ComposeAvatarResponseUseCase {
  ComposedAvatarResponse execute({
    required String text,
    required List<RecordedSign> dictionarySigns,
    int transitionFrames = 8,
  }) {
    final cleanedText = text.trim();
    if (cleanedText.isEmpty) {
      return ComposedAvatarResponse(
        originalText: text,
        matchedSigns: const [],
        missingWords: const [],
        frames: const [],
        wordStartFrames: const [],
      );
    }

    final signLookup = <String, RecordedSign>{};
    int maxPhraseWords = 1;

    for (final sign in dictionarySigns) {
      final norm = _normalizeToken(sign.word);
      if (norm.isEmpty) continue;
      signLookup[norm] = sign;
      final wordCount = norm.split(' ').length;
      if (wordCount > maxPhraseWords) {
        maxPhraseWords = wordCount;
      }
    }

    final rawTokens = cleanedText
        .split(RegExp(r'\s+'))
        .where((t) => _normalizeToken(t).isNotEmpty)
        .toList();

    final matchedSigns = <RecordedSign>[];
    final missingWords = <String>[];

    int i = 0;
    while (i < rawTokens.length) {
      RecordedSign? bestMatch;
      int consumedCount = 1;

      final maxSpan = math.min(maxPhraseWords, rawTokens.length - i);
      for (int span = maxSpan; span >= 1; span--) {
        final candidatePhrase = rawTokens
            .sublist(i, i + span)
            .map(_normalizeToken)
            .where((t) => t.isNotEmpty)
            .join(' ');
        final found = signLookup[candidatePhrase];
        if (found != null) {
          bestMatch = found;
          consumedCount = span;
          break;
        }
      }

      if (bestMatch != null) {
        matchedSigns.add(bestMatch);
      } else {
        missingWords.add(rawTokens[i]);
      }
      i += consumedCount;
    }

    if (matchedSigns.isEmpty) {
      return ComposedAvatarResponse(
        originalText: text,
        matchedSigns: const [],
        missingWords: missingWords,
        frames: const [],
        wordStartFrames: const [],
      );
    }

    final synthesized = <SignFrameLandmarks>[];
    final wordStartFrames = <int>[];
    const int frameStepMs = 33;

    for (int sIdx = 0; sIdx < matchedSigns.length; sIdx++) {
      final sign = matchedSigns[sIdx];
      wordStartFrames.add(synthesized.length);

      for (final frame in sign.frames) {
        final idx = synthesized.length;
        synthesized.add(
          SignFrameLandmarks(
            frameIndex: idx,
            timestampMs: idx * frameStepMs,
            hands: frame.hands,
          ),
        );
      }

      if (sIdx < matchedSigns.length - 1 &&
          sign.frames.isNotEmpty &&
          matchedSigns[sIdx + 1].frames.isNotEmpty &&
          transitionFrames > 0) {
        final lastFrame = sign.frames.last;
        final nextFirstFrame = matchedSigns[sIdx + 1].frames.first;
        final blend = _blendFrames(
          from: lastFrame,
          to: nextFirstFrame,
          steps: transitionFrames,
          startIndex: synthesized.length,
          frameStepMs: frameStepMs,
        );
        synthesized.addAll(blend);
      }
    }

    return ComposedAvatarResponse(
      originalText: text,
      matchedSigns: matchedSigns,
      missingWords: missingWords,
      frames: synthesized,
      wordStartFrames: wordStartFrames,
    );
  }

  List<SignFrameLandmarks> _blendFrames({
    required SignFrameLandmarks from,
    required SignFrameLandmarks to,
    required int steps,
    required int startIndex,
    required int frameStepMs,
  }) {
    final fromValid = from.hands.where((h) => h.isValid).toList();
    final toValid = to.hands.where((h) => h.isValid).toList();
    final blended = <SignFrameLandmarks>[];

    for (int s = 1; s <= steps; s++) {
      final t = s / (steps + 1);
      final smoothT = t * t * (3.0 - 2.0 * t);
      final handsCount = math.max(fromValid.length, toValid.length);
      final interpHands = <HandPose>[];

      for (int h = 0; h < handsCount; h++) {
        final hFrom = h < fromValid.length
            ? fromValid[h]
            : (h < toValid.length ? toValid[h] : null);
        final hTo = h < toValid.length
            ? toValid[h]
            : (h < fromValid.length ? fromValid[h] : null);
        if (hFrom == null || hTo == null) continue;

        final points = List<LandmarkPoint>.generate(21, (pIdx) {
          final p1 = hFrom.landmarks[pIdx];
          final p2 = hTo.landmarks[pIdx];
          return LandmarkPoint(
            x: p1.x + (p2.x - p1.x) * smoothT,
            y: p1.y + (p2.y - p1.y) * smoothT,
            z: p1.z + (p2.z - p1.z) * smoothT,
          );
        });

        interpHands.add(
          HandPose(
            landmarks: points,
            confidence: (hFrom.confidence + hTo.confidence) / 2.0,
            handedness: hTo.handedness ?? hFrom.handedness,
          ),
        );
      }

      final frameIdx = startIndex + s - 1;
      blended.add(
        SignFrameLandmarks(
          frameIndex: frameIdx,
          timestampMs: frameIdx * frameStepMs,
          hands: interpHands,
        ),
      );
    }

    return blended;
  }

  String _normalizeToken(String raw) {
    const accents = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'À': 'A',
      'È': 'E',
      'Ì': 'I',
      'Ò': 'O',
      'Ù': 'U',
    };

    final upper = raw.toUpperCase();
    final buffer = StringBuffer();
    for (final rune in upper.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(accents[ch] ?? ch);
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'[^A-Z0-9Ñ\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
