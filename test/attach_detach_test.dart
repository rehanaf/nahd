import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/models/figure.dart';

Figure _figureWithHostChildAndAttachedObject() {
  final fig = Figure();
  final p0 = fig.addPoint(0, 0);
  final p1 = fig.addPoint(100, 0);
  final p2 = fig.addPoint(200, 0);
  final p3 = fig.addPoint(100, 50);
  final p4 = fig.addPoint(150, 50);

  fig.createSegment('line', p0, p1); // segment A (host)
  fig.createSegment('line', p1, p2); // segment B (child of A at the joint)
  fig.createSegment('line', p3, p4); // segment C (will be attached)
  fig.rootIndices = [p0, p3];
  return fig;
}

void main() {
  group('attach / detach', () {
    test('detaching attached object keeps the host child segment', () {
      final fig = _figureWithHostChildAndAttachedObject();
      final hostChild = fig.segments[1];
      final attached = fig.segments[2];
      final joint = 1;

      // Mirror the attach tool: mark the host joint, merge C's root into it,
      // then remember exactly which segments were dragged.
      fig.points[joint].isAttached = true;
      final newJoint = fig.joinPoints(3, joint);
      fig.setAttachedSegments(newJoint, [attached.id]);

      final detached = fig.detachAttachedAt(newJoint);
      expect(detached, isNotNull);
      expect(detached!.segmentIds, contains(attached.id));
      expect(detached.segmentIds, isNot(contains(hostChild.id)));

      final stillHostChild = fig.getSegment(hostChild.id)!;
      final detachedSeg = fig.getSegment(attached.id)!;
      expect(stillHostChild.point1Index, joint,
          reason: 'B must stay connected to A');
      expect(stillHostChild.point2Index, 2);
      expect(detachedSeg.point1Index, detached.newRoot,
          reason: 'only C moves to the new root');
      expect(fig.points[joint].isAttached, isFalse);
      expect(fig.attachedSegments.containsKey(joint), isFalse);
      expect(fig.rootIndices, contains(detached.newRoot));
    });

    test('attachment bookkeeping survives clone and JSON round-trip', () {
      final fig = _figureWithHostChildAndAttachedObject();
      final attached = fig.segments[2];
      fig.points[1].isAttached = true;
      final joint = fig.joinPoints(3, 1);
      fig.setAttachedSegments(joint, [attached.id]);

      for (final restored in [fig.clone(), Figure.fromJsonString(fig.exportToJson())]) {
        expect(restored.attachedSegments[joint], [attached.id]);
        final detached = restored.detachAttachedAt(joint);
        expect(detached, isNotNull);
        expect(detached!.segmentIds, [attached.id]);
        expect(restored.getSegment(attached.id)!.point1Index, detached.newRoot);
        expect(restored.getSegment(fig.segments[1].id)!.point1Index, 1);
      }
    });
  });
}
