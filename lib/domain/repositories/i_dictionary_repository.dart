import '../entities/recorded_sign.dart';

abstract class IDictionaryRepository {
  Future<void> initialize();
  bool get isLoaded;
  List<RecordedSign> get allSigns;
  RecordedSign? getSignById(String id);
  Future<void> saveRecordedSign(RecordedSign sign);
  Future<void> deleteRecordedSign(String id);
  Future<void> clearAllSigns();
  Future<String> exportDictionaryJson();
  Future<int> importDictionaryJson(String jsonString);
}
