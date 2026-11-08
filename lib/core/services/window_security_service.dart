import 'package:flutter/services.dart';

/// Servicio de seguridad de ventana para mitigar OWASP M6 (Inadequate Privacy Controls).
///
/// Gestiona la bandera nativa FLAG_SECURE en Android para prevenir capturas de pantalla,
/// grabacion no autorizada y persistencia de instantaneas en el conmutador de tareas (App Switcher).
class WindowSecurityService {
  static const MethodChannel _channel =
      MethodChannel('com.academic.asl.sign_language_app/security');

  /// Habilita o deshabilita la proteccion de ventana contra capturas.
  static Future<void> setSecureMode(bool enable) async {
    try {
      await _channel.invokeMethod('setSecureFlag', {'enable': enable});
    } catch (_) {}
  }

  /// Consulta el estado actual de la proteccion de ventana.
  static Future<bool> isSecureModeActive() async {
    try {
      final bool? active =
          await _channel.invokeMethod<bool>('isSecureFlagActive');
      return active ?? false;
    } catch (_) {
      return false;
    }
  }
}
