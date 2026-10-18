class FaceBounds {
  final double left;
  final double top;
  final double width;
  final double height;

  const FaceBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceBounds &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'FaceBounds(left: $left, top: $top, width: $width, height: $height)';
}
