import 'landmark_point.dart';

class HandPose {
  final List<LandmarkPoint> landmarks;
  final double confidence;
  final String? handedness;

  const HandPose({
    required this.landmarks,
    this.confidence = 1.0,
    this.handedness,
  });

  bool get isValid => landmarks.length >= 21;

  LandmarkPoint get wrist => landmarks[0];
  LandmarkPoint get thumbTip => landmarks[4];
  LandmarkPoint get indexTip => landmarks[8];
  LandmarkPoint get middleBase => landmarks[9];
  LandmarkPoint get middleTip => landmarks[12];
  LandmarkPoint get ringTip => landmarks[16];
  LandmarkPoint get pinkyTip => landmarks[20];

  Map<String, dynamic> toJson() => {
        'landmarks': landmarks.map((l) => l.toJson()).toList(),
        'confidence': confidence,
        if (handedness != null) 'handedness': handedness,
      };

  factory HandPose.fromJson(Map<String, dynamic> json) {
    final list = (json['landmarks'] as List<dynamic>?)
            ?.map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return HandPose(
      landmarks: list,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      handedness: json['handedness'] as String?,
    );
  }
}
