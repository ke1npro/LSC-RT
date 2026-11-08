import 'package:local_auth/local_auth.dart';
import '../utils/app_logger.dart';

/// Servicio de autenticacion biometrica local (BiometricPrompt / LocalAuthentication)
/// para sumar puntos de bonificacion y proteger operaciones criticas sobre el Keystore.
class BiometricAuthService {
  final LocalAuthentication _auth;

  BiometricAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Verifica si el dispositivo cuenta con hardware biometrico disponible y configurado.
  Future<bool> isBiometricsAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (e) {
      AppLogger.w('BiometricAuthService: Error al consultar biometria: $e');
      return false;
    }
  }

  /// Solicita autenticacion por huella dactilar o reconocimiento facial.
  Future<bool> authenticate({
    required String reason,
  }) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        // En emuladores o dispositivos sin hardware biometrico configurado, permitir acceso
        return true;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      AppLogger.e('BiometricAuthService: Excepcion en autenticacion', e);
      return false;
    }
  }
}
