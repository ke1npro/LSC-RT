import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/core/utils/dictionary_import_validator.dart';
import 'package:sign_language_app/core/utils/temp_media_sweeper.dart';
import 'package:sign_language_app/data/datasources/encrypted_file_datasource.dart';
import 'package:sign_language_app/data/datasources/secure_storage_datasource.dart';
import 'package:sign_language_app/data/repositories/dictionary_repository_impl.dart';
import 'package:sign_language_app/domain/entities/hand_pose.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/entities/recorded_sign.dart';

RecordedSign makeSign({String id = 'hola_1', String word = 'HOLA', int frames = 5}) {
  return RecordedSign(
    id: id,
    word: word,
    category: 'Saludos',
    requiredHands: 1,
    fps: 30,
    detectionRate: 0.95,
    averageConfidence: 0.9,
    totalTakesEvaluated: 1,
    createdAt: DateTime(2026, 11, 17),
    frames: List.generate(
      frames,
      (i) => SignFrameLandmarks(
        frameIndex: i,
        timestampMs: i * 33,
        hands: [
          HandPose(
            landmarks: List.generate(21, (k) => LandmarkPoint(x: k * 0.01, y: 0.5, z: 0.0)),
            confidence: 0.9,
          ),
        ],
      ),
    ),
  );
}

void main() {
  late Directory tmp;
  late SecureStorageDataSource secure;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secure = SecureStorageDataSource();
    tmp = Directory.systemTemp.createTempSync('lsc_sec_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('H-09 AES-256-GCM: archivo cifrado y autenticado', () {
    test('cifra y descifra; el texto plano no aparece en el archivo', () async {
      final crypto = EncryptedFileDataSource(secure);
      final file = File('${tmp.path}/x.enc');
      await crypto.writeEncrypted(file, utf8.encode('SECRETO-BIOMETRICO-123'));

      final raw = await file.readAsBytes();
      expect(utf8.decode(raw, allowMalformed: true).contains('SECRETO'), isFalse);
      expect(utf8.decode(await crypto.readDecrypted(file)), 'SECRETO-BIOMETRICO-123');
    });

    test('dos cifrados del mismo texto producen salidas distintas (nonce aleatorio)', () async {
      final crypto = EncryptedFileDataSource(secure);
      final a = await crypto.encrypt(utf8.encode('mismo'));
      final b = await crypto.encrypt(utf8.encode('mismo'));
      expect(a, isNot(equals(b)));
    });

    test('detecta manipulacion de un solo byte', () async {
      final crypto = EncryptedFileDataSource(secure);
      final enc = await crypto.encrypt(utf8.encode('datos importantes'));
      final tampered = Uint8List.fromList(enc)..[enc.length - 20] ^= 0x01;
      expect(() => crypto.decrypt(tampered), throwsA(isA<EncryptedFileException>()));
    });

    test('la llave vive en el almacen seguro y no es texto plano del diccionario', () async {
      final crypto = EncryptedFileDataSource(secure);
      await crypto.encrypt(utf8.encode('x'));
      final key = await secure.readStrict(EncryptedFileDataSource.keyName);
      expect(key, isNotNull);
      expect(base64Decode(key!).length, 32);
    });
  });

  group('Diccionario cifrado en reposo', () {
    test('guardar -> archivo .enc sin texto legible -> recargar con nueva instancia', () async {
      final repo = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo.initialize();
      await repo.saveRecordedSign(makeSign());

      final encFile = File('${tmp.path}/lsc_dictionary.enc');
      expect(encFile.existsSync(), isTrue);
      final text = utf8.decode(await encFile.readAsBytes(), allowMalformed: true);
      expect(text.contains('HOLA'), isFalse);
      expect(text.contains('landmarks'), isFalse);

      final repo2 = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo2.initialize();
      expect(repo2.allSigns.length, 1);
      expect(repo2.allSigns.first.word, 'HOLA');
      expect(repo2.allSigns.first.frameCount, 5);
    });

    test('migra el JSON en texto plano heredado: lo cifra y borra el original', () async {
      final legacy = File('${tmp.path}/lsc_custom_dictionary.json');
      legacy.writeAsStringSync(jsonEncode([makeSign().toJson()]));

      final repo = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo.initialize();

      expect(repo.allSigns.length, 1);
      expect(legacy.existsSync(), isFalse);
      expect(File('${tmp.path}/lsc_dictionary.enc').existsSync(), isTrue);
    });

    test('archivo manipulado se pone en cuarentena y no rompe la app', () async {
      final repo = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo.initialize();
      await repo.saveRecordedSign(makeSign());

      final f = File('${tmp.path}/lsc_dictionary.enc');
      final bytes = f.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xFF;
      f.writeAsBytesSync(bytes);

      final repo2 = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo2.initialize();
      expect(repo2.allSigns, isEmpty);
      expect(File('${tmp.path}/lsc_dictionary.enc.corrupt').existsSync(), isTrue);
    });

    test('importacion rechaza señas con estructura maliciosa y acepta las validas', () async {
      final repo = DictionaryRepositoryImpl(EncryptedFileDataSource(secure), baseDir: tmp);
      await repo.initialize();

      final bad = makeSign(id: 'malo').toJson();
      (bad['frames'] as List)[0]['hands'][0]['landmarks'].removeLast(); // 20 puntos
      final badId = makeSign(id: '../../etc/passwd').toJson();
      final good = makeSign(id: 'bueno_1', word: 'GRACIAS').toJson();

      final imported = await repo.importDictionaryJson(
        jsonEncode({'signs': [bad, badId, good]}),
      );
      expect(imported, 1);
      expect(repo.allSigns.single.word, 'GRACIAS');
    });
  });

  group('M4 DictionaryImportValidator', () {
    test('rechaza NaN, Infinity y coordenadas fuera de rango', () {
      final nan = makeSign().toJson();
      (nan['frames'] as List)[0]['hands'][0]['landmarks'][0]['x'] = double.nan;
      expect(DictionaryImportValidator.isValidSignJson(nan), isFalse);

      final inf = makeSign().toJson();
      (inf['frames'] as List)[0]['hands'][0]['landmarks'][3]['y'] = double.infinity;
      expect(DictionaryImportValidator.isValidSignJson(inf), isFalse);

      final far = makeSign().toJson();
      (far['frames'] as List)[0]['hands'][0]['landmarks'][3]['z'] = 9999.0;
      expect(DictionaryImportValidator.isValidSignJson(far), isFalse);
    });

    test('rechaza demasiados frames, 3 manos y requiredHands invalido', () {
      expect(
        DictionaryImportValidator.isValidSignJson(makeSign(frames: 401).toJson()),
        isFalse,
      );

      final three = makeSign().toJson();
      final hand = (three['frames'] as List)[0]['hands'][0];
      (three['frames'] as List)[0]['hands'] = [hand, hand, hand];
      expect(DictionaryImportValidator.isValidSignJson(three), isFalse);

      final hands = makeSign().toJson()..['requiredHands'] = 7;
      expect(DictionaryImportValidator.isValidSignJson(hands), isFalse);
    });

    test('acepta una seña legitima', () {
      expect(DictionaryImportValidator.isValidSignJson(makeSign().toJson()), isTrue);
    });
  });

  group('H-10 barrido de videos temporales', () {
    test('elimina .mp4 huerfanos y conserva otros archivos', () async {
      final video = File('${tmp.path}/REC123.mp4')..writeAsBytesSync([1, 2, 3]);
      final nested = Directory('${tmp.path}/sub')..createSync();
      final video2 = File('${nested.path}/clip.MP4')..writeAsBytesSync([1]);
      final other = File('${tmp.path}/keep.txt')..writeAsStringSync('ok');

      final removed = await TempMediaSweeper.sweep(overrideDir: tmp);

      expect(removed, 2);
      expect(video.existsSync(), isFalse);
      expect(video2.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });
}
