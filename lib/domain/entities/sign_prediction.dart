class SignPrediction {
  final String label;
  final double confidence;

  const SignPrediction({
    required this.label,
    required this.confidence,
  });

  bool get isRecognized => label != '?' && label != '-' && confidence >= 0.50;

  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(1)}%)';
}
