import 'landmark_point.dart';

class ArmSkeleton {
  final LandmarkPoint wrist;
  final LandmarkPoint elbow;
  final LandmarkPoint shoulder;
  final LandmarkPoint sternum;
  final bool isRightArm;

  const ArmSkeleton({
    required this.wrist,
    required this.elbow,
    required this.shoulder,
    required this.sternum,
    required this.isRightArm,
  });
}
