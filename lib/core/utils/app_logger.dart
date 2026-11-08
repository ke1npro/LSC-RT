import 'package:flutter/foundation.dart';

/// Logger de seguridad que garantiza la supresion absoluta de trazas en Release.
///
/// Mitiga OWASP M1 y M8 evitando que detalles de la arquitectura, sensores o
/// excepciones internas queden expuestas en Android Logcat o consolas de sistema.
class AppLogger {
  AppLogger._();

  /// Emite un mensaje de depuracion UNICAMENTE en modo Debug (kDebugMode).
  /// En modo Release es un no-op garantizado.
  static void d(String message) {
    if (kDebugMode) {
      debugPrint('[LSC-DEBUG] $message');
    }
  }

  /// Emite una advertencia de depuracion unicamente en modo Debug.
  static void w(String message) {
    if (kDebugMode) {
      debugPrint('[LSC-WARN] $message');
    }
  }

  /// Emite un error sanitizado unicamente en modo Debug.
  /// En Release nunca emite trazas ni detalles internos al logcat del sistema operativo.
  static void e(String message, [dynamic error]) {
    if (kDebugMode) {
      debugPrint('[LSC-ERROR] $message ${error != null ? ": $error" : ""}');
    }
  }
}
