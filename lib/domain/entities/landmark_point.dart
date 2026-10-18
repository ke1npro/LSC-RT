class LandmarkPoint {
  final double x;
  final double y;
  final double z;

  const LandmarkPoint({
    required this.x,
    required this.y,
    this.z = 0.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LandmarkPoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'LandmarkPoint(x: $x, y: $y, z: $z)';
}
