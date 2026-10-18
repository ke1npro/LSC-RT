import 'dart:convert';
import '../../domain/repositories/i_sign_repository.dart';
import '../datasources/local_storage_datasource.dart';

class SignRepositoryImpl implements ISignRepository {
  final LocalStorageDataSource _localStorage;
  final Map<String, List<List<double>>> _signDatabase = {};
  bool _isLoaded = false;

  SignRepositoryImpl(this._localStorage);

  @override
  bool get isLoaded => _isLoaded;

  @override
  int get calibratedCount => _signDatabase.keys.length;

  @override
  Map<String, List<List<double>>> get signDatabase =>
      Map.unmodifiable(_signDatabase);

  @override
  Future<void> initialize() async {
    _signDatabase.clear();
    // 1. Cargar base de datos LSC desde assets
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
          _signDatabase[k] = list;
        });
      }
    } catch (_) {}

    // 2. Cargar calibraciones personalizadas locales
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
          _signDatabase[k] = list;
        });
      }
    } catch (_) {}

    _isLoaded = _signDatabase.isNotEmpty;
  }

  @override
  Future<void> saveSign(String letter, List<List<double>> samples) async {
    _signDatabase[letter] = samples;
    _isLoaded = true;
    try {
      final jsonStr = jsonEncode(_signDatabase);
      await _localStorage.setString('custom_lsc_db', jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> clearCustomSigns() async {
    await _localStorage.remove('custom_lsc_db');
    await initialize();
  }
}
