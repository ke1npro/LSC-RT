import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/dictionary_import_validator.dart';
import '../../core/utils/security_input_validator.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../datasources/encrypted_file_datasource.dart';

/// Diccionario de señas grabadas. Los landmarks de las manos del usuario son datos biometricos,
/// por eso se persisten SIEMPRE cifrados con AES-256-GCM (llave en Android Keystore).
class DictionaryRepositoryImpl implements IDictionaryRepository {
  final EncryptedFileDataSource _crypto;
  final Directory? _baseDirOverride;
  final Map<String, RecordedSign> _signsMap = {};
  bool _isLoaded = false;

  static const String _encryptedFileName = 'lsc_dictionary.enc';
  static const String _legacyPlainFileName = 'lsc_custom_dictionary.json';

  DictionaryRepositoryImpl(this._crypto, {Directory? baseDir})
      : _baseDirOverride = baseDir;

  @override
  bool get isLoaded => _isLoaded;

  @override
  List<RecordedSign> get allSigns => List.unmodifiable(_signsMap.values.toList());

  @override
  RecordedSign? getSignById(String id) => _signsMap[id];

  Future<Directory> _dir() async =>
      _baseDirOverride ?? await getApplicationDocumentsDirectory();

  Future<File> _encFile() async => File('${(await _dir()).path}/$_encryptedFileName');
  Future<File> _legacyFile() async => File('${(await _dir()).path}/$_legacyPlainFileName');

  @override
  Future<void> initialize() async {
    _signsMap.clear();
    try {
      final enc = await _encFile();
      if (await enc.exists()) {
        final plain = await _crypto.readDecrypted(enc);
        _loadFromJsonString(utf8.decode(plain));
      }

      // Migracion: version anterior guardaba el JSON en texto plano. Se cifra y se elimina.
      final legacy = await _legacyFile();
      if (await legacy.exists()) {
        try {
          _loadFromJsonString(await legacy.readAsString());
          await _persist();
        } finally {
          await legacy.delete();
        }
      }
    } catch (e) {
      AppLogger.e('DictionaryRepositoryImpl: no se pudo abrir el diccionario cifrado', e);
      await _quarantineCorruptFile();
    } finally {
      _isLoaded = true;
    }
  }

  void _loadFromJsonString(String content) {
    if (content.trim().isEmpty) return;
    final decoded = jsonDecode(content);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['signs'] is List ? decoded['signs'] as List : const []);
    for (final item in list) {
      if (!DictionaryImportValidator.isValidSignJson(item)) continue;
      final sign = RecordedSign.fromJson(Map<String, dynamic>.from(item as Map));
      if (SecurityInputValidator.sanitizeSignKey(sign.word) != null) {
        _signsMap[sign.id] = sign;
      }
    }
  }

  /// Si el archivo no autentica (manipulado o llave perdida) se aparta, no se sobrescribe en silencio.
  Future<void> _quarantineCorruptFile() async {
    try {
      final enc = await _encFile();
      if (await enc.exists()) {
        await enc.rename('${enc.path}.corrupt');
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final file = await _encFile();
    final jsonStr = jsonEncode(_signsMap.values.map((s) => s.toJson()).toList());
    await _crypto.writeEncrypted(file, utf8.encode(jsonStr));
  }

  RecordedSign _sanitize(RecordedSign sign) {
    final word = SecurityInputValidator.sanitizeSignKey(sign.word);
    if (word == null) throw ArgumentError('Nombre de seña inválido');
    final category = SecurityInputValidator.sanitizeSearchQuery(sign.category);
    return sign.copyWith(
      word: word,
      category: category.isEmpty ? 'General' : category,
    );
  }

  @override
  Future<void> saveRecordedSign(RecordedSign sign) async {
    if (sign.frames.isEmpty) throw ArgumentError('Seña sin frames');
    final clean = _sanitize(sign);
    _signsMap[clean.id] = clean;
    await _persist();
  }

  @override
  Future<void> deleteRecordedSign(String id) async {
    if (_signsMap.remove(id) != null) {
      await _persist();
    }
  }

  @override
  Future<void> clearAllSigns() async {
    _signsMap.clear();
    await _persist();
  }

  @override
  Future<String> exportDictionaryJson() async {
    final payload = {
      'format': 'LSC_OFFLINE_DICTIONARY',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'signCount': _signsMap.length,
      'signs': _signsMap.values.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  @override
  Future<int> importDictionaryJson(String jsonString) async {
    if (jsonString.trim().isEmpty) return 0;
    if (jsonString.length > DictionaryImportValidator.maxImportChars) {
      throw const FormatException('El archivo supera el tamaño máximo permitido');
    }

    final dynamic decoded = jsonDecode(jsonString);
    final List<dynamic> rawSigns;
    if (decoded is List) {
      rawSigns = decoded;
    } else if (decoded is Map && decoded['signs'] is List) {
      rawSigns = decoded['signs'] as List<dynamic>;
    } else {
      throw const FormatException('Formato de exportación JSON inválido');
    }
    if (rawSigns.length > DictionaryImportValidator.maxSigns) {
      throw const FormatException('Demasiadas señas en el archivo');
    }

    int imported = 0;
    for (final item in rawSigns) {
      if (!DictionaryImportValidator.isValidSignJson(item)) continue;
      try {
        final sign = RecordedSign.fromJson(Map<String, dynamic>.from(item as Map));
        final clean = _sanitize(sign);
        _signsMap[clean.id] = clean;
        imported++;
      } catch (_) {
        // Seña rechazada por nombre/estructura invalida: se omite sin abortar el resto.
      }
    }

    if (imported > 0) await _persist();
    return imported;
  }
}
