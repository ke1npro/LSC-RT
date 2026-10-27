import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/avatar_theme.dart';
import '../../data/datasources/avatar_motion_datasource.dart';
import '../../domain/entities/avatar_sign_data.dart';

class AvatarViewModel extends ChangeNotifier {
  final AvatarMotionDataSource motionDataSource;

  bool _isInitialized = false;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  final List<AvatarSignData> _sentenceSequence = [];

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

  AvatarViewModel(this.motionDataSource);

  bool get isInitialized => _isInitialized;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  List<AvatarSignData> get sentenceSequence => List.unmodifiable(_sentenceSequence);
  bool get isPlaying => _isPlaying;
  int get currentFrameIndex => _currentFrameIndex;
  int get totalFrames => _playbackFrames.length;
  double get playbackSpeed => _playbackSpeed;
  AvatarTheme get theme => _theme;
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
    _isInitialized = true;
    notifyListeners();
  }

  List<String> get categories {
    final cats = ['Todos', ...motionDataSource.getCategories()];
    return cats;
  }

  List<AvatarSignData> get filteredSigns {
    var signs = motionDataSource.allSigns;
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
    _searchQuery = query;
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
