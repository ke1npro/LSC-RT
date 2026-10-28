import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/entities/landmark_point.dart';
import 'vision_datasource.dart';

class PlatformVisionDataSource implements VisionDataSource {
  HandLandmarkerPlugin? _handLandmarkerPlugin;
  FaceDetector? _faceDetector;
  final _handController = StreamController<List<HandPose>>.broadcast();
  final _faceController = StreamController<List<FaceBounds>>.broadcast();

  StreamSubscription? _rawHandSub;
  bool _isProcessingHand = false;
  DateTime _lastHandTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProcessingFace = false;
  int _frameCounter = 0;
  bool _initialized = false;

  int _rotationDegrees = 270; // Por defecto 270° para orientación vertical correcta sin inversión (dedos arriba)
  bool _faceDetectionEnabled = false;
  bool _useGpu = false;

  static LandmarkPoint rotateLandmark(LandmarkPoint lm, int degrees) {
    final deg = (degrees % 360 + 360) % 360;
    switch (deg) {
      case 90:
        // Rotación de 90° en sentido horario (corrige la vista 90° antihoraria)
        return LandmarkPoint(x: (1.0 - lm.y).clamp(0.0, 1.0), y: lm.x.clamp(0.0, 1.0), z: lm.z);
      case 180:
        return LandmarkPoint(x: (1.0 - lm.x).clamp(0.0, 1.0), y: (1.0 - lm.y).clamp(0.0, 1.0), z: lm.z);
      case 270:
        return LandmarkPoint(x: lm.y.clamp(0.0, 1.0), y: (1.0 - lm.x).clamp(0.0, 1.0), z: lm.z);
      case 0:
      default:
        return lm;
    }
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Stream<List<HandPose>> get handStream => _handController.stream;

  @override
  Stream<List<FaceBounds>> get faceStream => _faceController.stream;

  @override
  void setRotation(int degrees) {
    _rotationDegrees = (degrees % 360 + 360) % 360;
  }

  @override
  void setFaceDetectionEnabled(bool enabled) {
    _faceDetectionEnabled = enabled;
  }

  @override
  void setUseGpu(bool useGpu) {
    if (_useGpu == useGpu) return;
    _useGpu = useGpu;
    if (_initialized && Platform.isAndroid) {
      _setupHandLandmarker();
    }
  }

  void _setupHandLandmarker() {
    try {
      _rawHandSub?.cancel();
      _rawHandSub = null;
      _handLandmarkerPlugin?.dispose();
      _handLandmarkerPlugin = null;

      _handLandmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.45,
        delegate: _useGpu ? HandLandmarkerDelegate.gpu : HandLandmarkerDelegate.cpu,
      );

      _rawHandSub = _handLandmarkerPlugin?.landmarkStream.listen((rawHands) {
        _isProcessingHand = false;
        final detected = rawHands.map((h) {
          final landmarks = h.landmarks.map((lm) {
            final rawPoint = LandmarkPoint(x: lm.x, y: lm.y, z: lm.z);
            return rotateLandmark(rawPoint, _rotationDegrees);
          }).toList();
          return HandPose(landmarks: landmarks, confidence: 1.0);
        }).toList();
        _handController.add(detected);
      });
    } catch (e) {
      debugPrint('Aviso: Error configurando HandLandmarker con delegate (${_useGpu ? "GPU" : "CPU"}): $e');
    }
  }

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _initialized = true;
      return;
    }

    _setupHandLandmarker();

    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
    } catch (e) {
      debugPrint('Aviso: FaceDetector no disponible: $e');
    }

    _initialized = true;
  }

  @override
  void processFrame(dynamic image, int sensorOrientation) {
    if (image is! CameraImage) return;
    if (!_initialized || _handLandmarkerPlugin == null) return;
    _frameCounter++;

    final now = DateTime.now();

    // 1. Control de contrapresión estricto (Zero-Drop Lock):
    // Si MediaPipe está ocupado procesando el fotograma previo, descartar el actual
    // para no saturar memoria JNI ni la CPU de Android.
    // Timeout de recuperación rápida (120ms) solo en caso de fotograma perdido.
    final bool canProcessHand = !_isProcessingHand ||
        now.difference(_lastHandTime).inMilliseconds > 120;

    if (canProcessHand && image.planes.length >= 3) {
      _isProcessingHand = true;
      _lastHandTime = now;
      try {
        _handLandmarkerPlugin!.processFrame(image, sensorOrientation);
      } catch (e) {
        debugPrint('Error en handLandmarker.processFrame: $e');
        _isProcessingHand = false;
      }
    }

    // 2. Detección facial liviana a baja frecuencia (1 de cada 60 fotogramas)
    // ÚNICAMENTE si el usuario activó la detección facial en ajustes.
    if (_faceDetectionEnabled &&
        _frameCounter % 60 == 0 &&
        !_isProcessingFace &&
        _faceDetector != null) {
      _isProcessingFace = true;
      _processFaceFrame(image, sensorOrientation).whenComplete(() {
        _isProcessingFace = false;
      });
    }
  }

  Future<void> _processFaceFrame(CameraImage image, int sensorOrientation) async {
    try {
      final inputImage = _inputImageFromCameraImage(image, sensorOrientation);
      if (inputImage == null) return;
      final faces = await _faceDetector!.processImage(inputImage);
      final double imgW = image.width.toDouble();
      final double imgH = image.height.toDouble();
      final double rotW = (sensorOrientation == 90 || sensorOrientation == 270) ? imgH : imgW;
      final double rotH = (sensorOrientation == 90 || sensorOrientation == 270) ? imgW : imgH;

      final boundsList = faces.map((f) {
        final b = f.boundingBox;
        final double uNorm = (b.left / rotW).clamp(0.0, 1.0);
        final double vNorm = (b.top / rotH).clamp(0.0, 1.0);
        final double wNorm = (b.width / rotW).clamp(0.0, 1.0);
        final double hNorm = (b.height / rotH).clamp(0.0, 1.0);

        if (sensorOrientation == 90) {
          return FaceBounds(
            left: vNorm,
            top: (1.0 - uNorm - wNorm).clamp(0.0, 1.0),
            width: hNorm,
            height: wNorm,
          );
        } else if (sensorOrientation == 270) {
          return FaceBounds(
            left: (1.0 - vNorm - hNorm).clamp(0.0, 1.0),
            top: uNorm,
            width: hNorm,
            height: wNorm,
          );
        } else {
          return FaceBounds(left: uNorm, top: vNorm, width: wNorm, height: hNorm);
        }
      }).toList();
      _faceController.add(boundsList);
    } catch (_) {}
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, int sensorOrientation) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _rawHandSub?.cancel();
    try {
      await _faceDetector?.close();
    } catch (_) {}
    await _handController.close();
    await _faceController.close();
  }
}

VisionDataSource createVisionDataSource() => PlatformVisionDataSource();
