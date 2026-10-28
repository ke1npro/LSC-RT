import 'dart:convert';
import '../../domain/repositories/i_sign_repository.dart';
import '../datasources/local_storage_datasource.dart';

class SignRepositoryImpl implements ISignRepository {
  final LocalStorageDataSource _localStorage;
  final Map<String, List<List<double>>> _factoryDatabase = {};
  final Map<String, List<List<double>>> _customOverrides = {};
  final Map<String, List<List<double>>> _signDatabase = {};
  Map<String, List<List<double>>>? _cachedDatabase;
  bool _isLoaded = false;

  SignRepositoryImpl(this._localStorage);

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

    // 1. Cargar base de datos canónica de fábrica desde assets
    try {
      final lscJsonStr =
          await _localStorage.loadAssetString('assets/lsc_database.json');
      if (lscJsonStr.trim().isNotEmpty && lscJsonStr.trim() != '{}') {
        final decoded = jsonDecode(lscJsonStr) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final list = (v as List<dynamic>).map((sample) {
            return (sample as List<dynamic>)
                .map((val) => (val as num).toDouble())
                .toList();
          }).toList();
          _factoryDatabase[k] = list;
          _signDatabase[k] = list;
        });
      }
    } catch (_) {}

    // 2. Cargar overrides personalizados del usuario desde LocalStorage
    try {
      final customJson = await _localStorage.getString('custom_lsc_db');
      if (customJson != null && customJson.isNotEmpty) {
        final decoded = jsonDecode(customJson) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final list = (v as List<dynamic>).map((sample) {
            return (sample as List<dynamic>)
                .map((val) => (val as num).toDouble())
                .toList();
          }).toList();
          _customOverrides[k] = list;
          _signDatabase[k] = list; // Aplica override
        });
      }
    } catch (_) {}

    _isLoaded = _signDatabase.isNotEmpty;
  }

  @override
  Future<void> saveSign(String letter, List<List<double>> samples) async {
    _customOverrides[letter] = samples;
    _signDatabase[letter] = samples;
    _cachedDatabase = null;
    _isLoaded = true;
    try {
      final jsonStr = jsonEncode(_customOverrides);
      await _localStorage.setString('custom_lsc_db', jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> clearCustomSigns() async {
    await _localStorage.remove('custom_lsc_db');
    _customOverrides.clear();
    _signDatabase.clear();
    _signDatabase.addAll(_factoryDatabase);
    _cachedDatabase = null;
    _isLoaded = _signDatabase.isNotEmpty;
  }
}
