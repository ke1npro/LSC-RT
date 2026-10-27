import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class ITtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  bool get isEnabled;
  void setEnabled(bool enabled);
  void dispose();
}

class TtsService implements ITtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isEnabled = true;
  String _lastSpoken = '';
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool get isEnabled => _isEnabled;

  @override
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      stop();
    }
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage('es-ES');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
    } catch (e) {
      debugPrint('TtsService: Error al inicializar TTS: $e');
      _isInitialized = false;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!_isEnabled) return;
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    // Control de redundancia: evitar repetir la misma palabra en menos de 2.5 segundos
    final now = DateTime.now();
    if (_lastSpoken == cleanText &&
        now.difference(_lastSpokenTime).inMilliseconds < 2500) {
      return;
    }

    _lastSpoken = cleanText;
    _lastSpokenTime = now;

    // Ejecución completamente asíncrona sin bloquear hilos de renderizado o cámara
    unawaited(_executeSpeech(cleanText));
  }

  Future<void> _executeSpeech(String text) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TtsService: Excepción no bloqueante en speak: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    stop();
  }
}
