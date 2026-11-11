import 'package:flutter/foundation.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/recorded_sign.dart';
import '../../domain/repositories/i_dictionary_repository.dart';

class DictionaryViewModel extends ChangeNotifier {
  final IDictionaryRepository _dictionaryRepository;

  DictionaryViewModel(this._dictionaryRepository);

  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = 'Todas';
  int? _selectedHandsFilter; // null = Todas, 1 = 1 mano, 2 = 2 manos

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;
  int? get selectedHandsFilter => _selectedHandsFilter;

  List<RecordedSign> get allSigns => _dictionaryRepository.allSigns;

  List<String> get categories {
    final set = <String>{'Todas'};
    for (final s in allSigns) {
      if (s.category.trim().isNotEmpty) {
        set.add(s.category.trim());
      }
    }
    return set.toList();
  }

  List<RecordedSign> get filteredSigns {
    return allSigns.where((sign) {
      if (_selectedCategory != 'Todas' &&
          sign.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_selectedHandsFilter != null &&
          sign.requiredHands != _selectedHandsFilter) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchWord = sign.word.toLowerCase().contains(q);
        final matchCat = sign.category.toLowerCase().contains(q);
        if (!matchWord && !matchCat) return false;
      }
      return true;
    }).toList();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _dictionaryRepository.initialize();
    } catch (e) {
      AppLogger.e('DictionaryViewModel: Error al inicializar', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSelectedHandsFilter(int? hands) {
    _selectedHandsFilter = hands;
    notifyListeners();
  }

  Future<void> deleteSign(String id) async {
    try {
      await _dictionaryRepository.deleteRecordedSign(id);
      notifyListeners();
    } catch (e) {
      AppLogger.e('DictionaryViewModel: Error al eliminar seña', e);
      rethrow;
    }
  }

  Future<void> clearAll() async {
    try {
      await _dictionaryRepository.clearAllSigns();
      notifyListeners();
    } catch (e) {
      AppLogger.e('DictionaryViewModel: Error al limpiar diccionario', e);
      rethrow;
    }
  }

  Future<String> exportDictionary() async {
    return await _dictionaryRepository.exportDictionaryJson();
  }

  Future<int> importDictionary(String jsonString) async {
    _isLoading = true;
    notifyListeners();
    try {
      final count = await _dictionaryRepository.importDictionaryJson(jsonString);
      return count;
    } catch (e) {
      AppLogger.e('DictionaryViewModel: Error al importar diccionario', e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
