import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/avatar_theme.dart';
import '../../core/utils/security_input_validator.dart';
import '../../data/datasources/avatar_motion_datasource.dart';
import '../../domain/entities/avatar_sign_data.dart';
import '../../domain/repositories/i_dictionary_repository.dart';
import '../../domain/services/sign_frame_avatar_adapter.dart';
import '../../domain/usecases/resolve_body_pose_usecase.dart';

class AvatarViewModel extends ChangeNotifier {
  final AvatarMotionDataSource motionDataSource;
  final IDictionaryRepository? dictionaryRepository;

  bool _isInitialized = false;
  bool _isRefreshing = false;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  final List<AvatarSignData> _sentenceSequence = [];
  List<AvatarSignData> _dictionaryAvatarSigns = [];

  // Estado de reproducción cinemática
  List<AvatarFrame> _playbackFrames = [];
  List<int> _wordBoundaryIndices = [];
  int _currentFrameIndex = 0;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  Timer? _playbackTimer;

  // Estelas cinemáticas
  final List<Offset> _rightHandTrail = [];
  final List<Offset> _leftHandTrail = [];

  // Tema del Avatar
  AvatarTheme _theme = AvatarTheme.neon();

  AvatarViewModel(
    this.motionDataSource, {
    this.dictionaryRepository,
  });

  bool get isInitialized => _isInitialized;
  bool get isRefreshing => _isRefreshing;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  List<AvatarSignData> get sentenceSequence => List.unmodifiable(_sentenceSequence);
  bool get isPlaying => _isPlaying;
  int get currentFrameIndex => _currentFrameIndex;
  int get totalFrames => _playbackFrames.length;
  double get playbackSpeed => _playbackSpeed;
  AvatarTheme get theme => _theme;

  /// Tema efectivo para la palabra actualmente en reproducción (ajusta relación de aspecto).
  AvatarTheme get currentFrameTheme {
    if (_sentenceSequence.isEmpty) return _theme;
    final idx = currentWordIndex.clamp(0, _sentenceSequence.length - 1);
    final aspect = _sentenceSequence[idx].sourceAspect;
    if (aspect == null) return _theme;
    return _theme.copyWith(sourceAspect: aspect);
  }
  List<Offset> get rightHandTrail => List.unmodifiable(_rightHandTrail);
  List<Offset> get leftHandTrail => List.unmodifiable(_leftHandTrail);

  AvatarFrame? get currentFrame {
    if (_playbackFrames.isEmpty || _currentFrameIndex >= _playbackFrames.length) {
      return null;
    }
    return _playbackFrames[_currentFrameIndex];
  }

  int get currentWordIndex {
    if (_sentenceSequence.isEmpty || _wordBoundaryIndices.isEmpty) return 0;
    for (int i = _wordBoundaryIndices.length - 1; i >= 0; i--) {
      if (_currentFrameIndex >= _wordBoundaryIndices[i]) {
        return i.clamp(0, _sentenceSequence.length - 1);
      }
    }
    return 0;
  }

  String get currentWordDisplayName {
    if (_sentenceSequence.isEmpty) return '';
    final idx = currentWordIndex;
    if (idx >= 0 && idx < _sentenceSequence.length) {
      return _sentenceSequence[idx].displayName;
    }
    return '';
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await motionDataSource.initialize();
    if (dictionaryRepository != null && !dictionaryRepository!.isLoaded) {
      await dictionaryRepository!.initialize();
    }
    _rebuildDictionarySigns();
    _isInitialized = true;
    notifyListeners();
  }

  /// Recarga el catálogo del banco de señas y el diccionario del usuario.
  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();
    try {
      await motionDataSource.refresh();
      if (dictionaryRepository != null && !dictionaryRepository!.isLoaded) {
        await dictionaryRepository!.initialize();
      }
      _rebuildDictionarySigns();
      _isInitialized = motionDataSource.isLoaded || _dictionaryAvatarSigns.isNotEmpty;
      if (_selectedCategory != 'Todos' && !categories.contains(_selectedCategory)) {
        _selectedCategory = 'Todos';
      }
      _preparePlaybackFrames();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void _rebuildDictionarySigns() {
    final repo = dictionaryRepository;
    if (repo == null) {
      _dictionaryAvatarSigns = const [];
      return;
    }
    final poseUseCase = ResolveBodyPoseUseCase();
    _dictionaryAvatarSigns = repo.allSigns
        .where((s) => s.frames.isNotEmpty)
        .map((s) => SignFrameAvatarAdapter.toAvatarSignData(s, poseUseCase))
        .toList(growable: false);
  }

  List<AvatarSignData> get _allCombinedSigns {
    if (_dictionaryAvatarSigns.isEmpty) return motionDataSource.allSigns;
    return [..._dictionaryAvatarSigns, ...motionDataSource.allSigns];
  }

  List<String> get categories {
    final set = <String>{
      ...motionDataSource.getCategories(),
      ..._dictionaryAvatarSigns.map((s) => s.category),
    };
    final sorted = set.toList()..sort();
    return ['Todos', ...sorted];
  }

  List<AvatarSignData> get filteredSigns {
    var signs = _allCombinedSigns;
    if (_selectedCategory != 'Todos') {
      signs = signs.where((s) => s.category == _selectedCategory).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      signs = signs.where((s) {
        return s.displayName.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q);
      }).toList();
    }
    return signs;
  }

  void setSelectedCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = SecurityInputValidator.sanitizeSearchQuery(query);
    notifyListeners();
  }

  void addWordToSentence(AvatarSignData sign) {
    _sentenceSequence.add(sign);
    _preparePlaybackFrames();
    notifyListeners();
  }

  void removeWordAt(int index) {
    if (index >= 0 && index < _sentenceSequence.length) {
      _sentenceSequence.removeAt(index);
      _preparePlaybackFrames();
      notifyListeners();
    }
  }

  void clearSentence() {
    _sentenceSequence.clear();
    stop();
    _playbackFrames.clear();
    _wordBoundaryIndices.clear();
    notifyListeners();
  }

  void setTheme(AvatarTheme theme) {
    _theme = theme;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    if (_isPlaying) {
      _restartTimer();
    }
    notifyListeners();
  }

  void _preparePlaybackFrames() {
    stop();
    _playbackFrames = motionDataSource.synthesizeSentence(_sentenceSequence);
    _wordBoundaryIndices = [];

    // Calcular límites de cuadro para cada palabra de la secuencia
    int currentOffset = 0;
    for (int i = 0; i < _sentenceSequence.length; i++) {
      _wordBoundaryIndices.add(currentOffset);
      currentOffset += _sentenceSequence[i].totalFrames;
      if (i < _sentenceSequence.length - 1) {
        currentOffset += 8; // 8 cuadros de transición Hermite
      }
    }
    _currentFrameIndex = 0;
  }

  void play() {
    if (_playbackFrames.isEmpty) {
      _preparePlaybackFrames();
    }
    if (_playbackFrames.isEmpty) return;

    _isPlaying = true;
    _restartTimer();
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _currentFrameIndex = 0;
    _rightHandTrail.clear();
    _leftHandTrail.clear();
    notifyListeners();
  }

  void replay() {
    stop();
    play();
  }

  void seekToFrame(int frameIndex) {
    if (_playbackFrames.isEmpty) return;
    _currentFrameIndex = frameIndex.clamp(0, _playbackFrames.length - 1);
    notifyListeners();
  }

  void _restartTimer() {
    _playbackTimer?.cancel();
    final intervalMs = (1000 / (24.0 * _playbackSpeed)).round().clamp(10, 200);
    _playbackTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _advanceFrame();
    });
  }

  void _advanceFrame() {
    if (_playbackFrames.isEmpty) return;

    if (_currentFrameIndex < _playbackFrames.length - 1) {
      _currentFrameIndex++;
      _updateTrails(_playbackFrames[_currentFrameIndex]);
      notifyListeners();
    } else {
      // Fin de la secuencia
      stop();
    }
  }

  void _updateTrails(AvatarFrame frame) {
    if (!_theme.showTrail) return;

    // Rastrear muñeca derecha
    final rw = frame.pose['right_wrist'];
    if (rw != null) {
      _rightHandTrail.add(Offset(rw.x, rw.y));
      if (_rightHandTrail.length > _theme.trailLength) {
        _rightHandTrail.removeAt(0);
      }
    }

    // Rastrear muñeca izquierda
    final lw = frame.pose['left_wrist'];
    if (lw != null) {
      _leftHandTrail.add(Offset(lw.x, lw.y));
      if (_leftHandTrail.length > _theme.trailLength) {
        _leftHandTrail.removeAt(0);
      }
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}
