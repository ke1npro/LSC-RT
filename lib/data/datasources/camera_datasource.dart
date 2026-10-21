import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraDataSource {
  List<CameraDescription> _cameras;
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;
  bool _isSwitching = false;
  bool _isPermissionDenied = false;
  String? _errorMessage;

  CameraDataSource(List<CameraDescription> cameras) : _cameras = List.from(cameras) {
    if (_cameras.isNotEmpty) {
      final frontIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _selectedCameraIndex = (frontIdx != -1) ? frontIdx : 0;
    }
  }

  List<CameraDescription> get cameras => _cameras;
  CameraController? get controller => _controller;
  int get selectedCameraIndex => _selectedCameraIndex;
  bool get isInitialized =>
      !_isSwitching &&
      _isInitialized &&
      _controller != null &&
      _controller!.value.isInitialized &&
      !_controller!.value.hasError;

  bool get isSwitching => _isSwitching;
  bool get isPermissionDenied => _isPermissionDenied;
  String? get errorMessage => _errorMessage;

  CameraDescription? get currentCamera =>
      _cameras.isNotEmpty && _selectedCameraIndex < _cameras.length
          ? _cameras[_selectedCameraIndex]
          : null;

  bool _isPermissionException(dynamic error) {
    if (error is CameraException) {
      final code = error.code.toLowerCase();
      final desc = (error.description ?? '').toLowerCase();
      return code.contains('permission') ||
          code.contains('accessdenied') ||
          code.contains('restricted') ||
          desc.contains('permission') ||
          desc.contains('denied');
    }
    final str = error.toString().toLowerCase();
    return str.contains('permission') ||
        str.contains('accessdenied') ||
        str.contains('denied');
  }

  Future<void> initializeCamera({
    Function(CameraImage image, int sensorOrientation)? onFrame,
  }) async {
    _errorMessage = null;
    _isPermissionDenied = false;

    // Si la lista de cámaras estaba vacía (ej. permisos no aceptados al inicio), intentar consultar
    if (_cameras.isEmpty) {
      try {
        final available = await availableCameras();
        if (available.isNotEmpty) {
          _cameras = List.from(available);
          final frontIdx = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
          );
          _selectedCameraIndex = (frontIdx != -1) ? frontIdx : 0;
        }
      } catch (e) {
        debugPrint('Error al consultar availableCameras: $e');
        if (_isPermissionException(e)) {
          _isPermissionDenied = true;
          _errorMessage =
              'Permiso de cámara denegado. Concede acceso a la cámara en ajustes para usar la app.';
        } else {
          _errorMessage = 'No se detectaron cámaras en este dispositivo.';
        }
        _isInitialized = false;
        return;
      }
    }

    if (_cameras.isEmpty) {
      _errorMessage = 'No se detectaron cámaras disponibles en este dispositivo.';
      _isInitialized = false;
      return;
    }

    await disposeCamera();

    final desc = _cameras[_selectedCameraIndex];
    final newController = CameraController(
      desc,
      ResolutionPreset.low,
      enableAudio: false,
    );

    try {
      await newController.initialize();
      _controller = newController;
      _isInitialized = true;
      _errorMessage = null;
      _isPermissionDenied = false;

      if (!kIsWeb && onFrame != null) {
        await newController.startImageStream((CameraImage image) {
          if (!_isInitialized || _controller == null) return;
          onFrame(image, desc.sensorOrientation);
        });
      }
    } catch (e) {
      debugPrint('Error inicializando CameraDataSource: $e');
      _isInitialized = false;
      try {
        await newController.dispose();
      } catch (_) {}

      if (_isPermissionException(e)) {
        _isPermissionDenied = true;
        _errorMessage =
            'Permiso de cámara denegado. Concede permisos para usar el reconocimiento.';
      } else {
        _errorMessage = 'No se pudo abrir la cámara. Revisa que otra app no la esté usando.';
      }
    }
  }

  Future<void> switchCamera({
    Function(CameraImage image, int sensorOrientation)? onFrame,
  }) async {
    if (_cameras.length < 2 || _isSwitching) return;
    _isSwitching = true;

    // Desasignar inmediatamente _controller para que los widgets en árbol
    // pasen a estado de transición sin evaluar un controller en disposición
    final oldController = _controller;
    _controller = null;
    _isInitialized = false;

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
    }

    try {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await initializeCamera(onFrame: onFrame);
    } catch (e) {
      debugPrint('Error en switchCamera: $e');
      _errorMessage = 'Error al cambiar de cámara.';
    } finally {
      _isSwitching = false;
    }
  }

  Future<void> disposeCamera() async {
    final oldController = _controller;
    _controller = null;
    _isInitialized = false;

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
    }
  }
}
