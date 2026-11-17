import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'app_logger.dart';

/// H-10 (M6/M9): los clips .mp4 de practica contienen el rostro del usuario. Se borran al terminar
/// cada sesion, pero si la app se cierra a la fuerza quedarian huerfanos en la cache. Este barrido
/// de arranque elimina cualquier video temporal residual.
class TempMediaSweeper {
  TempMediaSweeper._();

  static const List<String> _videoExtensions = ['.mp4', '.3gp', '.mkv', '.webm'];

  static Future<int> sweep({Directory? overrideDir}) async {
    int removed = 0;
    try {
      final dir = overrideDir ?? await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.toLowerCase();
        if (_videoExtensions.any(name.endsWith)) {
          try {
            await entity.delete();
            removed++;
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.w('TempMediaSweeper: no se pudo barrer la cache: $e');
    }
    return removed;
  }
}
