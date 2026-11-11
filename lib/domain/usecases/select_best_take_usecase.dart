import '../entities/sign_take_candidate.dart';

class BestTakeEvaluationResult {
  final SignTakeCandidate winner;
  final bool isAcceptable;
  final double bestRate;
  final double bestConfidence;
  final List<SignTakeCandidate> ranking;
  final double threshold;

  const BestTakeEvaluationResult({
    required this.winner,
    required this.isAcceptable,
    required this.bestRate,
    required this.bestConfidence,
    required this.ranking,
    this.threshold = 0.70,
  });
}

/// Evalúa entre 1 y 5 tomas candidatas y selecciona automáticamente la mejor
/// basándose en el porcentaje de fotogramas con detección válida de manos dentro
/// del segmento recortado, desempatando por confianza promedio de MediaPipe.
class SelectBestTakeUseCase {
  static const double defaultThreshold = 0.70;

  BestTakeEvaluationResult? execute({
    required List<SignTakeCandidate> takes,
    required int requiredHands,
    double threshold = defaultThreshold,
  }) {
    if (takes.isEmpty) return null;

    final sorted = List<SignTakeCandidate>.from(takes)..sort((a, b) {
      final rateA = a.detectionRate(requiredHands);
      final rateB = b.detectionRate(requiredHands);

      // Si la diferencia es menor a 0.1%, usar la confianza promedio como desempate
      if ((rateA - rateB).abs() < 0.001) {
        final confA = a.averageConfidence(requiredHands);
        final confB = b.averageConfidence(requiredHands);
        return confB.compareTo(confA);
      }
      return rateB.compareTo(rateA);
    });

    final winner = sorted.first;
    final bestRate = winner.detectionRate(requiredHands);
    final bestConfidence = winner.averageConfidence(requiredHands);
    final isAcceptable = bestRate >= threshold;

    return BestTakeEvaluationResult(
      winner: winner,
      isAcceptable: isAcceptable,
      bestRate: bestRate,
      bestConfidence: bestConfidence,
      ranking: sorted,
      threshold: threshold,
    );
  }
}
