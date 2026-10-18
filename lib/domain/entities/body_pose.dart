import 'arm_skeleton.dart';
import 'face_bounds.dart';
import 'hand_pose.dart';

class BodyPose {
  final List<HandPose> hands;
  final List<ArmSkeleton> arms;
  final FaceBounds? primaryFace;

  const BodyPose({
    this.hands = const [],
    this.arms = const [],
    this.primaryFace,
  });

  bool get hasHand => hands.isNotEmpty && hands.any((h) => h.isValid);
  bool get hasFace => primaryFace != null;

  HandPose? get primaryHand => hasHand ? hands.firstWhere((h) => h.isValid) : null;
  ArmSkeleton? get primaryArm => arms.isNotEmpty ? arms.first : null;

  static const empty = BodyPose();
}
