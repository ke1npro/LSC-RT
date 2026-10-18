import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraDataSource {
  final List<CameraDescription> _cameras;
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;

  CameraDataSource(this._cameras) {
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
  bool get isInitialized => _isInitialized && _controller != null && _controller!.value.isInitialized;
  CameraDescription? get currentCamera => _cameras.isNotEmpty ? _cameras[_selectedCameraIndex] : null;

  Future<void> initializeCamera({
    Function(CameraImage image, int sensorOrientation)? onFrame,
  }) async {
    if (_cameras.isEmpty) return;

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

      if (!kIsWeb && onFrame != null) {
        await newController.startImageStream((CameraImage image) {
          if (!_isInitialized) return;
          onFrame(image, desc.sensorOrientation);
        });
      }
    } catch (e) {
      debugPrint('Error inicializando CameraDataSource: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> switchCamera({
    Function(CameraImage image, int sensorOrientation)? onFrame,
  }) async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await initializeCamera(onFrame: onFrame);
  }

  Future<void> disposeCamera() async {
    if (_controller != null) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (_) {}
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
    _isInitialized = false;
  }
}
