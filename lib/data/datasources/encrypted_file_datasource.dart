import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_storage_datasource.dart';

class EncryptedFileException implements Exception {
  final String message;
  const EncryptedFileException(this.message);
  @override
  String toString() => 'EncryptedFileException: $message';
}

/// Archivo cifrado con AES-256-GCM (cifrado autenticado: detecta manipulacion).
///
/// La llave de 256 bits es aleatoria, se genera una sola vez y vive SOLO en Android Keystore
/// (via [SecureStorageDataSource.writeStrict]). Formato: "LSC1" | nonce(12) | ciphertext | tag(16).
/// Mitiga M9 (almacenamiento inseguro) y M10 (criptografia insuficiente).
class EncryptedFileDataSource {
  static const List<int> _magic = [0x4C, 0x53, 0x43, 0x31]; // "LSC1"
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const String keyName = 'dictionary_aes256_key';

  final SecureStorageDataSource _secure;
  final AesGcm _algorithm = AesGcm.with256bits();
  SecretKey? _cachedKey;

  EncryptedFileDataSource(this._secure);

  Future<SecretKey> _getOrCreateKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final stored = await _secure.readStrict(keyName);
    if (stored != null && stored.isNotEmpty) {
      final bytes = base64Decode(stored);
      if (bytes.length != 32) {
        throw const EncryptedFileException('Llave almacenada con longitud invalida');
      }
      return _cachedKey = SecretKey(bytes);
    }

    final newKey = await _algorithm.newSecretKey();
    final bytes = await newKey.extractBytes();
    await _secure.writeStrict(keyName, base64Encode(bytes));
    return _cachedKey = SecretKey(bytes);
  }

  Future<Uint8List> encrypt(List<int> plainBytes) async {
    final key = await _getOrCreateKey();
    final box = await _algorithm.encrypt(plainBytes, secretKey: key);
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  Future<List<int>> decrypt(Uint8List data) async {
    if (data.length < _magic.length + _nonceLength + _macLength) {
      throw const EncryptedFileException('Archivo cifrado demasiado corto');
    }
    for (int i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) {
        throw const EncryptedFileException('Cabecera de archivo invalida');
      }
    }
    final nonceEnd = _magic.length + _nonceLength;
    final macStart = data.length - _macLength;
    final box = SecretBox(
      data.sublist(nonceEnd, macStart),
      nonce: data.sublist(_magic.length, nonceEnd),
      mac: Mac(data.sublist(macStart)),
    );
    final key = await _getOrCreateKey();
    try {
      return await _algorithm.decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const EncryptedFileException(
          'Autenticacion fallida: archivo manipulado o llave distinta');
    }
  }

  /// Escritura atomica: archivo temporal + rename para no dejar un archivo a medias.
  Future<void> writeEncrypted(File file, List<int> plainBytes) async {
    final encrypted = await encrypt(plainBytes);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(encrypted, flush: true);
    await tmp.rename(file.path);
  }

  Future<List<int>> readDecrypted(File file) async {
    return decrypt(await file.readAsBytes());
  }
}
