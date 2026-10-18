import 'landmark_point.dart';

class HandPose {
  final List<LandmarkPoint> landmarks;
  final double confidence;

  const HandPose({
    required this.landmarks,
    this.confidence = 1.0,
  });

  bool get isValid => landmarks.length >= 21;

  LandmarkPoint get wrist => landmarks[0];
  LandmarkPoint get thumbTip => landmarks[4];
  LandmarkPoint get indexTip => landmarks[8];
  LandmarkPoint get middleBase => landmarks[9];
  LandmarkPoint get middleTip => landmarks[12];
  LandmarkPoint get ringTip => landmarks[16];
  LandmarkPoint get pinkyTip => landmarks[20];
}
