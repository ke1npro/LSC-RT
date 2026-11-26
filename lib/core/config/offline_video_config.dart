class OfflineVideoConfig {
  OfflineVideoConfig._();

  static const List<int> validFps = [30, 20, 15];
  static const List<String> validPresets = ['high', 'medium', 'low'];

  static const int defaultFps = 20;
  static const String defaultPreset = 'medium';

  static int maxDimensionForPreset(String preset) {
    switch (sanitizePreset(preset)) {
      case 'high':
        return 480;
      case 'low':
        return 256;
      case 'medium':
      default:
        return 360;
    }
  }

  static String labelForPreset(String preset) {
    switch (sanitizePreset(preset)) {
      case 'high':
        return 'Alta';
      case 'low':
        return 'Baja';
      case 'medium':
      default:
        return 'Media';
    }
  }

  static int sanitizeFps(int fps) {
    return validFps.contains(fps) ? fps : defaultFps;
  }

  static String sanitizePreset(String preset) {
    final normalized = preset.trim().toLowerCase();
    return validPresets.contains(normalized) ? normalized : defaultPreset;
  }
}
