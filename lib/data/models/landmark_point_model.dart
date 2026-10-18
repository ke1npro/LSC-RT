import '../../domain/entities/landmark_point.dart';

class LandmarkPointModel extends LandmarkPoint {
  const LandmarkPointModel({
    required super.x,
    required super.y,
    super.z = 0.0,
  });

  factory LandmarkPointModel.fromJson(Map<String, dynamic> json) {
    return LandmarkPointModel(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: json['z'] != null ? (json['z'] as num).toDouble() : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'z': z,
  };

  factory LandmarkPointModel.fromEntity(LandmarkPoint entity) {
    return LandmarkPointModel(x: entity.x, y: entity.y, z: entity.z);
  }
}
