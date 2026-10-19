/// Representación de un fotograma cinemático normalizado para DTW.
/// Contiene 8 coordenadas correspondientes a los codos y muñecas:
/// [codoIzqX, codoIzqY, codoDerX, codoDerY, munecaIzqX, munecaIzqY, munecaDerX, munecaDerY]
class DtwJointFrame {
  final List<double> values;

  const DtwJointFrame(this.values) : assert(values.length == 8, 'El fotograma debe tener 8 valores (4 articulaciones x 2 dimensiones)');

  double get elbowLeftX => values[0];
  double get elbowLeftY => values[1];
  double get elbowRightX => values[2];
  double get elbowRightY => values[3];
  double get wristLeftX => values[4];
  double get wristLeftY => values[5];
  double get wristRightX => values[6];
  double get wristRightY => values[7];
}

/// Secuencia cinemática normalizada a una longitud temporal fija (T = 16 fotogramas).
class DtwSequence {
  final List<DtwJointFrame> frames;

  const DtwSequence(this.frames) : assert(frames.length == 16, 'La secuencia DTW debe tener exactamente 16 fotogramas');

  /// Devuelve los datos como una lista plana de listas (16 x 8)
  List<List<double>> toMatrix() => frames.map((f) => f.values).toList();

  /// Crea una secuencia desde una matriz cruda de 16 x 8
  factory DtwSequence.fromMatrix(List<List<double>> matrix) {
    assert(matrix.length == 16, 'La matriz debe tener 16 filas');
    return DtwSequence(matrix.map((row) => DtwJointFrame(row)).toList());
  }
}

/// Plantilla de gesto registrada en el banco de referencias del usuario.
class DtwGestureTemplate {
  final int classId;
  final String name;
  final DtwSequence sequence;
  final DateTime registeredAt;

  DtwGestureTemplate({
    required this.classId,
    required this.name,
    required this.sequence,
    DateTime? registeredAt,
  }) : registeredAt = registeredAt ?? DateTime.now();
}

/// Resultado de la clasificación por kNN-DTW.
class DtwRecognitionResult {
  final int classId;
  final String name;
  final double distance;
  final double confidence;
  final bool isAccepted;

  const DtwRecognitionResult({
    required this.classId,
    required this.name,
    required this.distance,
    required this.confidence,
    required this.isAccepted,
  });

  @override
  String toString() =>
      'DtwRecognitionResult(name: $name, id: $classId, distance: ${distance.toStringAsFixed(2)}, confidence: ${(confidence * 100).toStringAsFixed(1)}%, accepted: $isAccepted)';
}
