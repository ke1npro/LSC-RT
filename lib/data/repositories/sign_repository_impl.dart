import 'dart:convert';
import '../../core/utils/security_input_validator.dart';
import '../../domain/repositories/i_sign_repository.dart';
import '../datasources/local_storage_datasource.dart';
import '../datasources/secure_storage_datasource.dart';

class SignRepositoryImpl implements ISignRepository {
  final LocalStorageDataSource _localStorage;
  final SecureStorageDataSource _secureStorage;
  final Map<String, List<List<double>>> _factoryDatabase = {};
  final Map<String, List<List<double>>> _customOverrides = {};
  final Map<String, List<List<double>>> _signDatabase = {};
  Map<String, List<List<double>>>? _cachedDatabase;
  bool _isLoaded = false;

  SignRepositoryImpl(
    this._localStorage, [
    SecureStorageDataSource? secureStorage,
  ]) : _secureStorage = secureStorage ??
            SecureStorageDataSource(legacyStorage: _localStorage);

  @override
  bool get isLoaded => _isLoaded;

  @override
  int get calibratedCount => _signDatabase.keys.length;

  @override
  int get factorySignsCount => _factoryDatabase.keys.length;

  @override
  int get customOverridesCount => _customOverrides.keys.length;

  @override
  bool get hasCustomOverrides => _customOverrides.isNotEmpty;

  @override
  Map<String, List<List<double>>> get signDatabase {
    _cachedDatabase ??= Map.unmodifiable(_signDatabase);
    return _cachedDatabase!;
  }

  @override
  Future<void> initialize() async {
    _factoryDatabase.clear();
    _customOverrides.clear();
    _signDatabase.clear();
    _cachedDatabase = null;

    // 1. Cargar base de datos canónica de fábrica desde assets con validacion defensiva
    try {
      final lscJsonStr =
          await _localStorage.loadAssetString('assets/lsc_database.json');
      if (lscJsonStr.trim().isNotEmpty && lscJsonStr.trim() != '{}') {
        final decoded = jsonDecode(lscJsonStr) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final sanitizedKey = SecurityInputValidator.sanitizeSignKey(k);
          final validSamples = SecurityInputValidator.validateSignSamples(v);
          if (sanitizedKey != null && validSamples.isNotEmpty) {
            _factoryDatabase[sanitizedKey] = validSamples;
            _signDatabase[sanitizedKey] = validSamples;
          }
        });
      }
    } catch (_) {}

    // 2. Cargar overrides personalizados del usuario desde SecureStorage cifrado en hardware
    try {
      final customJson = await _secureStorage.read('custom_lsc_db');
      if (customJson != null && customJson.isNotEmpty) {
        final decoded = jsonDecode(customJson) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final sanitizedKey = SecurityInputValidator.sanitizeSignKey(k);
          final validSamples = SecurityInputValidator.validateSignSamples(v);
          if (sanitizedKey != null && validSamples.isNotEmpty) {
            _customOverrides[sanitizedKey] = validSamples;
            _signDatabase[sanitizedKey] = validSamples; // Aplica override
          }
        });
      }
    } catch (_) {}

    _isLoaded = _signDatabase.isNotEmpty;
  }

  @override
  Future<void> saveSign(String letter, List<List<double>> samples) async {
    final sanitizedKey = SecurityInputValidator.sanitizeSignKey(letter);
    final validSamples = SecurityInputValidator.validateSignSamples(samples);
    if (sanitizedKey == null || validSamples.isEmpty) return;

    _customOverrides[sanitizedKey] = validSamples;
    _signDatabase[sanitizedKey] = validSamples;
    _cachedDatabase = null;
    _isLoaded = true;
    try {
      final jsonStr = jsonEncode(_customOverrides);
      await _secureStorage.write('custom_lsc_db', jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> clearCustomSigns() async {
    await _secureStorage.delete('custom_lsc_db');
    _customOverrides.clear();
    _signDatabase.clear();
    _signDatabase.addAll(_factoryDatabase);
    _cachedDatabase = null;
    _isLoaded = _signDatabase.isNotEmpty;
  }
}
