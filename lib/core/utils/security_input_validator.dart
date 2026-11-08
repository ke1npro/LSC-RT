/// Validador defensivo de entradas para mitigar OWASP M4 (Insufficient Input/Output Validation).
///
/// Previene inyecciones, corrupcion de memoria, desbordamientos de datos (buffer overflows)
/// y desestabilizacion matemática (NaN / Infinity) en los clasificadores de vision artificial.
class SecurityInputValidator {
  SecurityInputValidator._();

  static const int maxKeyLength = 32;
  static const int maxSamplesPerSign = 100;
  static const int maxSearchLength = 64;

  /// Sanitiza y valida la clave identificadora de una seña.
  /// Rechaza cadenas vacias, desproporcionadas o con caracteres de control.
  static String? sanitizeSignKey(String? rawKey) {
    if (rawKey == null) return null;
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty || trimmed.length > maxKeyLength) return null;
    final regex = RegExp(r'^[a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ _-]+$');
    if (!regex.hasMatch(trimmed)) return null;
    return trimmed;
  }

  /// Valida una muestra numérica asegurando que ningun valor sea NaN o Infinity,
  /// y restringiendo las coordenadas a un rango físico valido [-10.0, 10.0].
  static List<double>? validateNumericSample(dynamic rawSample) {
    if (rawSample is! List) return null;
    final result = <double>[];
    for (final val in rawSample) {
      if (val is! num) return null;
      final d = val.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      if (d < -10.0 || d > 10.0) return null;
      result.add(d);
    }
    return result;
  }

  /// Valida una coleccion de muestras de postura de forma estricta.
  static List<List<double>> validateSignSamples(dynamic rawSamples) {
    if (rawSamples is! List) return [];
    final validSamples = <List<double>>[];
    for (final s in rawSamples) {
      final valid = validateNumericSample(s);
      if (valid != null && valid.isNotEmpty) {
        validSamples.add(valid);
        if (validSamples.length >= maxSamplesPerSign) break;
      }
    }
    return validSamples;
  }

  /// Sanitiza consultas de busqueda en texto previniendo caracteres de control
  /// y acotando la longitud máxima.
  static String sanitizeSearchQuery(String? query) {
    if (query == null) return '';
    final cleaned = query.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return cleaned.length > maxSearchLength
        ? cleaned.substring(0, maxSearchLength)
        : cleaned;
  }
}
