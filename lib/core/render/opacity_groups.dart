import 'dart:ui';

/// Collects draw calls by the opacity they should be rendered with, then
/// composites every opacity bucket as ONE layer.
///
/// Drawing two overlapping parts with `alpha = 0.2` directly would make the
/// overlap darker (`0.36`) because the second part blends over the first.
/// Onion skin avoids this by painting the whole ghost opaquely into a layer and
/// fading the layer once. Opacity keyframes work the same way here: all shapes
/// that share an opacity form one flat, opaque image which is then faded once.
///
/// Buckets are emitted in first-seen order, so normal draw order is preserved
/// between different opacity values. Within a bucket the original insertion
/// order is kept.
class OpacityPaintGroups {
  final Map<double, List<VoidCallback>> _groups = <double, List<VoidCallback>>{};
  final List<double> _order = <double>[];

  bool get isEmpty => _order.isEmpty;

  /// Number of queued draws per opacity bucket (useful for tests).
  Map<double, int> get bucketSizes => Map.unmodifiable({
        for (final entry in _groups.entries) entry.key: entry.value.length,
      });

  /// Adds a draw operation at [opacity]. Invisible and invalid values are
  /// ignored; `1.0` is drawn directly without an extra offscreen layer.
  void add(double opacity, VoidCallback draw) {
    final value = opacity.isFinite ? opacity.clamp(0.0, 1.0) : 1.0;
    if (value <= 0.0001) return;
    // Quantise to 1/1000 to avoid float noise creating duplicate buckets.
    final bucket = (value * 1000).roundToDouble() / 1000;
    if (!_groups.containsKey(bucket)) _order.add(bucket);
    _groups.putIfAbsent(bucket, () => <VoidCallback>[]).add(draw);
  }

  /// Paints all collected operations onto [canvas].
  void paint(Canvas canvas) {
    for (final opacity in _order) {
      final draws = _groups[opacity]!;
      // Bypass saveLayer on Flutter Web to prevent CanvasKit black screen bug
      for (final draw in draws) {
        draw();
      }
    }
  }
}
