import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/security_input_validator.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../datasources/secure_storage_datasource.dart';

class DictionaryRepositoryImpl implements IDictionaryRepository {
  final SecureStorageDataSource? _secureStorage;
  final Map<String, RecordedSign> _signsMap = {};
  bool _isLoaded = false;
  File? _storageFile;

  static const String _dictionaryFileName = 'lsc_custom_dictionary.json';
  static const String _secureChecksumKey = 'dictionary_data_checksum';

  DictionaryRepositoryImpl([this._secureStorage]);

  @override
  bool get isLoaded => _isLoaded;

  @override
  List<RecordedSign> get allSigns => List.unmodifiable(_signsMap.values.toList());

  @override
  RecordedSign? getSignById(String id) => _signsMap[id];

  Future<File> _getFile() async {
    if (_storageFile != null) return _storageFile!;
    final dir = await getApplicationDocumentsDirectory();
    _storageFile = File('${dir.path}/$_dictionaryFileName');
    return _storageFile!;
  }

  @override
  Future<void> initialize() async {
    _signsMap.clear();
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final dynamic decoded = jsonDecode(content);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final sign = RecordedSign.fromJson(item);
                if (sign.id.isNotEmpty && sign.word.isNotEmpty) {
                  _signsMap[sign.id] = sign;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.e('DictionaryRepositoryImpl: Error al cargar diccionario local', e);
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _getFile();
      final list = _signsMap.values.map((s) => s.toJson()).toList();
      final jsonStr = jsonEncode(list);
      await file.writeAsString(jsonStr, flush: true);

      // Guardar hash en SecureStorage para verificación de integridad
      if (_secureStorage != null) {
        final checksum = jsonStr.hashCode.toString();
        await _secureStorage.write(_secureChecksumKey, checksum);
      }
    } catch (e) {
      AppLogger.e('DictionaryRepositoryImpl: Error al guardar cambios', e);
      rethrow;
    }
  }

  @override
  Future<void> saveRecordedSign(RecordedSign sign) async {
    final sanitizedWord = SecurityInputValidator.sanitizeSignKey(sign.word);
    if (sanitizedWord == null || sign.frames.isEmpty) {
      throw ArgumentError('Seña inválida o sin frames');
    }

    final sanitizedSign = sign.copyWith(word: sanitizedWord);
    _signsMap[sanitizedSign.id] = sanitizedSign;
    await _persist();
  }

  @override
  Future<void> deleteRecordedSign(String id) async {
    if (_signsMap.containsKey(id)) {
      _signsMap.remove(id);
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

    final dynamic decoded = jsonDecode(jsonString);
    List<dynamic> rawSigns = [];

    if (decoded is List) {
      rawSigns = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['signs'] is List) {
      rawSigns = decoded['signs'] as List<dynamic>;
    } else {
      throw const FormatException('Formato de exportación JSON inválido');
    }

    int importedCount = 0;
    for (final item in rawSigns) {
      if (item is Map<String, dynamic>) {
        final sign = RecordedSign.fromJson(item);
        final sanitized = SecurityInputValidator.sanitizeSignKey(sign.word);
        if (sanitized != null && sign.id.isNotEmpty && sign.frames.isNotEmpty) {
          _signsMap[sign.id] = sign.copyWith(word: sanitized);
          importedCount++;
        }
      }
    }

    if (importedCount > 0) {
      await _persist();
    }
    return importedCount;
  }
}
