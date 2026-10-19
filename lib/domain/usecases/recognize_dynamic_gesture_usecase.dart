import '../entities/dtw_gesture_sample.dart';
import '../entities/landmark_point.dart';
import '../services/chest_activity_detector.dart';
import '../services/dtw_classifier.dart';

/// Caso de uso para el reconocimiento continuo de señas dinámicas mediante kNN-DTW.
/// Coordina la detección de actividad por línea de pecho, el remuestreo a 16 fotogramas
/// y la clasificación elástica contra el banco de plantillas del usuario.
class RecognizeDynamicGestureUseCase {
  final DtwClassifier _classifier;
  final ChestActivityDetector _detector;
  final List<DtwGestureTemplate> _templates = [];

  RecognizeDynamicGestureUseCase({
    DtwClassifier? classifier,
    ChestActivityDetector? detector,
  })  : _classifier = classifier ?? const DtwClassifier(),
        _detector = detector ?? ChestActivityDetector();

  List<DtwGestureTemplate> get templates => List.unmodifiable(_templates);
  GestureTrackingState get trackingState => _detector.state;

  /// Registra una nueva plantilla de seña en el banco de referencias del usuario.
  void registerTemplate({
    required int classId,
    required String name,
    required List<List<double>> rawSequence,
  }) {
    final resampled = DtwClassifier.resampleSequence(rawSequence, targetLen: 16);
    final sequence = DtwSequence.fromMatrix(resampled);
    _templates.add(DtwGestureTemplate(
      classId: classId,
      name: name,
      sequence: sequence,
    ));
  }

  /// Limpia el banco de plantillas.
  void clearTemplates() {
    _templates.clear();
  }

  /// Reinicia el estado interno del detector de actividad.
  void resetDetector() {
    _detector.reset();
  }

  /// Procesa un fotograma entrante del flujo de video.
  /// Si un gesto dinámico culmina en este fotograma, ejecuta la clasificación y retorna el resultado.
  DtwRecognitionResult? processPoseFrame({
    required LandmarkPoint shoulderLeft,
    required LandmarkPoint shoulderRight,
    required LandmarkPoint elbowLeft,
    required LandmarkPoint elbowRight,
    required LandmarkPoint wristLeft,
    required LandmarkPoint wristRight,
    double? threshold,
  }) {
    final activeSegment = _detector.processFrame(
      shoulderLeft: shoulderLeft,
      shoulderRight: shoulderRight,
      elbowLeft: elbowLeft,
      elbowRight: elbowRight,
      wristLeft: wristLeft,
      wristRight: wristRight,
    );

    if (activeSegment != null) {
      return classifySequence(activeSegment, threshold: threshold);
    }
    return null;
  }

  /// Clasifica directamente una secuencia ya segmentada (utilidad clave para depuración y pruebas).
  DtwRecognitionResult? classifySequence(
    List<List<double>> rawSequence, {
    double? threshold,
  }) {
    if (rawSequence.length < 4 || _templates.isEmpty) return null;

    final resampled = DtwClassifier.resampleSequence(rawSequence, targetLen: 16);
    final querySequence = DtwSequence.fromMatrix(resampled);

    return _classifier.classify(
      querySequence,
      _templates,
      threshold: threshold,
    );
  }
}
