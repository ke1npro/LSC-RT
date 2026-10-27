abstract class ISignRepository {
  bool get isLoaded;
  int get calibratedCount;
  int get factorySignsCount;
  int get customOverridesCount;
  bool get hasCustomOverrides;
  Map<String, List<List<double>>> get signDatabase;

  Future<void> initialize();
  Future<void> saveSign(String letter, List<List<double>> samples);
  Future<void> clearCustomSigns();
}
