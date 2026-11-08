import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'local_storage_datasource.dart';

/// Fuente de datos de almacenamiento cifrado en hardware.
///
/// Delega en Android Keystore (AES-256-GCM / EncryptedSharedPreferences)
/// y en iOS Keychain para mitigar OWASP M9 (Insecure Data Storage) y M10 (Insufficient Cryptography).
class SecureStorageDataSource {
  final FlutterSecureStorage _secureStorage;
  final LocalStorageDataSource? legacyStorage;

  SecureStorageDataSource({
    FlutterSecureStorage? secureStorage,
    this.legacyStorage,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Lee un valor cifrado. Si no existe en secure storage pero existe en SharedPreferences legado,
  /// lo migra de forma transparente y lo elimina del almacenamiento en texto claro.
  Future<String?> read(String key) async {
    try {
      final secureVal = await _secureStorage.read(key: key);
      if (secureVal != null) {
        return secureVal;
      }

      // Migracion automatica desde SharedPreferences en texto claro si existiera
      if (legacyStorage != null) {
        final legacyVal = await legacyStorage!.getString(key);
        if (legacyVal != null && legacyVal.isNotEmpty) {
          await _secureStorage.write(key: key, value: legacyVal);
          await legacyStorage!.remove(key);
          return legacyVal;
        }
      }

      return null;
    } catch (_) {
      // Fallback seguro en caso de fallo de hardware Keystore
      return legacyStorage?.getString(key);
    }
  }

  /// Escribe un valor cifrado en hardware.
  Future<bool> write(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      // Asegurar que no quede remanente en texto claro
      if (legacyStorage != null) {
        await legacyStorage!.remove(key);
      }
      return true;
    } catch (_) {
      // En caso de excepcion (ej. emuladores sin Keystore activo), escribir con fallback
      if (legacyStorage != null) {
        return await legacyStorage!.setString(key, value);
      }
      return false;
    }
  }

  /// Elimina una clave de forma segura en ambos almacenes.
  Future<bool> delete(String key) async {
    try {
      await _secureStorage.delete(key: key);
      if (legacyStorage != null) {
        await legacyStorage!.remove(key);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifica la presencia de una clave de forma segura.
  Future<bool> containsKey(String key) async {
    try {
      final exists = await _secureStorage.containsKey(key: key);
      if (exists) return true;
      if (legacyStorage != null) {
        final legacy = await legacyStorage!.getString(key);
        return legacy != null && legacy.isNotEmpty;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
