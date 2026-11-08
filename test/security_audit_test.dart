import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language_app/core/services/window_security_service.dart';
import 'package:sign_language_app/core/utils/security_input_validator.dart';
import 'package:sign_language_app/data/datasources/local_storage_datasource.dart';
import 'package:sign_language_app/data/datasources/secure_storage_datasource.dart';
import 'package:sign_language_app/data/repositories/sign_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security Audit Tests (OWASP Mobile Top 10)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('H-04 / M9 & M10: SecureStorageDataSource migrates and stores sensitive data securely', () async {
      final legacy = LocalStorageDataSource();
      const testKey = 'custom_lsc_db';
      const testPayload = '{"A": [[0.1, 0.2, 0.3]]}';

      // 1. Simular dato legado en texto plano en SharedPreferences
      await legacy.setString(testKey, testPayload);
      expect(await legacy.getString(testKey), equals(testPayload));

      // 2. Inicializar SecureStorageDataSource con migracion automatica
      final secureStorage = SecureStorageDataSource(legacyStorage: legacy);

      // Al leer por primera vez, debe retornar el dato y haberlo migrado a SecureStorage
      final retrieved = await secureStorage.read(testKey);
      expect(retrieved, equals(testPayload));

      // El dato legado en SharedPreferences en texto claro debe haber sido eliminado
      final legacyAfter = await legacy.getString(testKey);
      expect(legacyAfter, isNull);

      // 3. Escribir nueva actualizacion sensible en SecureStorage
      const updatedPayload = '{"B": [[0.4, 0.5, 0.6]]}';
      final writeSuccess = await secureStorage.write(testKey, updatedPayload);
      expect(writeSuccess, isTrue);

      final secureRetrieved = await secureStorage.read(testKey);
      expect(secureRetrieved, equals(updatedPayload));

      // 4. Eliminar de forma segura
      await secureStorage.delete(testKey);
      expect(await secureStorage.read(testKey), isNull);
    });

    test('H-04 / M9: SignRepositoryImpl stores and clears custom calibrations in secure storage', () async {
      final legacy = LocalStorageDataSource();
      final secureStorage = SecureStorageDataSource(legacyStorage: legacy);
      final repo = SignRepositoryImpl(legacy, secureStorage);

      await repo.initialize();
      expect(repo.hasCustomOverrides, isFalse);

      // Guardar calibracion personalizada
      await repo.saveSign('Z', [
        [0.1, 0.2, 0.3, 0.4]
      ]);

      expect(repo.hasCustomOverrides, isTrue);
      expect(repo.customOverridesCount, equals(1));

      // Limpiar calibraciones de forma segura
      await repo.clearCustomSigns();
      expect(repo.hasCustomOverrides, isFalse);
      expect(repo.customOverridesCount, equals(0));
    });

    test('H-05 / M6: WindowSecurityService handles FLAG_SECURE method channel calls gracefully', () async {
      // En entorno de prueba unitaria sin host nativo, no debe lanzar excepciones no controladas
      await expectLater(WindowSecurityService.setSecureMode(true), completes);
      final isActive = await WindowSecurityService.isSecureModeActive();
      expect(isActive, isFalse); // Fallback seguro en entorno headless/test
    });

    test('H-06 / M4: SecurityInputValidator sanitizes keys, floats and search strings', () {
      // Claves de seña
      expect(SecurityInputValidator.sanitizeSignKey('Hola Mundo'), equals('Hola Mundo'));
      expect(SecurityInputValidator.sanitizeSignKey(''), isNull);
      expect(SecurityInputValidator.sanitizeSignKey('a' * 50), isNull); // Excede longitud maxima
      expect(SecurityInputValidator.sanitizeSignKey('Sign<script>'), isNull); // Caracteres invalidos

      // Validacion numerica contra NaN e Infinity
      expect(SecurityInputValidator.validateNumericSample([0.1, 0.5, 0.9]), equals([0.1, 0.5, 0.9]));
      expect(SecurityInputValidator.validateNumericSample([0.1, double.nan, 0.9]), isNull);
      expect(SecurityInputValidator.validateNumericSample([0.1, double.infinity, 0.9]), isNull);
      expect(SecurityInputValidator.validateNumericSample([0.1, 999.0, 0.9]), isNull); // Out of bounds

      // Sanitizacion de busqueda
      expect(SecurityInputValidator.sanitizeSearchQuery('  Gracias\x00\x1F  '), equals('Gracias'));
      expect(SecurityInputValidator.sanitizeSearchQuery('b' * 100).length, equals(64));
    });
  });
}
