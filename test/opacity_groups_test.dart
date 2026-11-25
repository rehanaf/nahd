import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/render/opacity_groups.dart';

void _noop() {}

void main() {
  test('draws sharing an opacity are queued in one composite bucket', () {
    final groups = OpacityPaintGroups();
    groups.add(0.2, _noop);
    groups.add(0.2, _noop);
    groups.add(0.2, _noop);
    groups.add(0.5, _noop);

    // Two overlapping head/body parts at 0.2 are painted into a single layer,
    // so the 0.2 fade is applied once instead of once per part.
    expect(groups.bucketSizes, {0.2: 3, 0.5: 1});
  });

  test('opacity zero is skipped and invalid values fall back to 1.0', () {
    final groups = OpacityPaintGroups();
    groups.add(0, _noop);
    groups.add(-1, _noop);
    groups.add(double.nan, _noop);
    groups.add(1, _noop);

    expect(groups.bucketSizes, {1.0: 2});
    expect(groups.isEmpty, isFalse);
  });
}
