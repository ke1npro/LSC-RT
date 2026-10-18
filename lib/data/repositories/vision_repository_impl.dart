import 'dart:async';
import '../../domain/entities/face_bounds.dart';
import '../../domain/entities/hand_pose.dart';
import '../../domain/repositories/i_vision_repository.dart';
import '../datasources/vision_datasource.dart';

class VisionRepositoryImpl implements IVisionRepository {
  final VisionDataSource _dataSource;

  VisionRepositoryImpl(this._dataSource);

  @override
  bool get isInitialized => _dataSource.isInitialized;

  @override
  Stream<List<HandPose>> get handStream => _dataSource.handStream;

  @override
  Stream<List<FaceBounds>> get faceStream => _dataSource.faceStream;

  @override
  Future<void> initialize() => _dataSource.initialize();

  @override
  void processFrame(dynamic image, int sensorOrientation) =>
      _dataSource.processFrame(image, sensorOrientation);

  @override
  Future<void> dispose() => _dataSource.dispose();
}
