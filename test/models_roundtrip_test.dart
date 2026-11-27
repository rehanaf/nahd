import 'package:flutter_test/flutter_test.dart';

import 'package:id_animate/core/models/figure.dart';
import 'package:id_animate/core/models/figure_animation.dart';
import 'package:id_animate/core/models/segment.dart';

void main() {
  test('Point2 JSON round-trip', () {
    const json = {'x': 12.5, 'y': -3.25, 'isAttached': false, 'static': false};
    final p = Point2.fromJson({'x': 12.5, 'y': -3.25});
    expect(p.x, 12.5);
    expect(p.y, -3.25);
    expect(p.toJson(), json);
  });

  test('Figure JSON round-trip preserves segments and points', () {
    final fig = Figure('Stickman')
      ..canvasWidth = 800
      ..canvasHeight = 600
      ..fps = 12;
    final p1 = fig.addPoint(0, 0);
    final p2 = fig.addPoint(40, 0);
    final p3 = fig.addPoint(20, -40);
    fig.createSegment('line', p1, p2)
      ..color = '#ff0000'
      ..width = 4;
    fig.createSegment('circle', p2, p3)
      ..fillColor = '#00ff00'
      ..type = 'circle';
    fig.setFigureVisibility(p1, 0.5, false);

    final decoded = Figure.fromJsonString(fig.exportToJson());

    expect(decoded.name, 'Stickman');
    expect(decoded.points.length, 3);
    expect(decoded.segments.length, 2);
    expect(decoded.segments[0].color, '#ff0000');
    expect(decoded.segments[0].width, 4);
    expect(decoded.segments[1].type, 'circle');
    expect(decoded.segments[1].fillColor, '#00ff00');
    expect(decoded.getFigureVisibility(p1, 0.5), false);
    expect(decoded.getFigureVisibility(p1, 0.0), true);
    expect(decoded.canvasWidth, 800);
    expect(decoded.fps, 12);
    expect(decoded.groups.length, 1);
    expect(decoded.groups.first.id, Figure.defaultGroupId);
    expect(decoded.groupOf(decoded.segments.first.id), Figure.defaultGroupId);
  });

  test('FigureAnimation JSON round-trip preserves tracks and keyframes', () {
    final anim = FigureAnimation();
    anim.setPointPose(0.0, 0, 10.0, 20.0);
    anim.setPointPose(1.0, 0, 30.0, 40.0);
    anim.setPointPose(2.0, 0, 5.0, 6.0);

    final decoded = FigureAnimation.fromJsonString(anim.exportToJson());

    expect(decoded.duration, 3.0);
    final track = decoded.getTrack(0);
    expect(track, isNotNull);
    expect(track!.keyframes.length, 3);
    expect(track.keyframes[0].x, 10.0);
    expect(track.keyframes[2].y, 6.0);
    final mid = track.getValue(1.5);
    expect(mid, isNotNull);
    expect(mid!.x, 17.5);
    expect(mid.y, 23.0);
  });

  test('Segment JSON round-trip preserves collision flag', () {
    final seg = Segment('image')
      ..point1Index = 0
      ..point2Index = 1
      ..imageDataList = ['data:image/png;base64,AAAA']
      ..isCollision = true;

    final decoded = Segment.fromJson(seg.toJson());

    expect(decoded.isCollision, isTrue);
    expect(decoded.imageDataList, ['data:image/png;base64,AAAA']);
    expect(decoded.point1Index, 0);
    expect(decoded.point2Index, 1);

    // Missing key defaults to false (backward compatible).
    final legacy = Segment.fromJson(const {'type': 'line'});
    expect(legacy.isCollision, isFalse);
  });

  test('Figure collision flag round-trips per figure', () {
    final fig = Figure('Collide')
      ..points.addAll([Point2(0, 0), Point2(40, 0)])
      ..rootIndices.add(0);
    fig.createSegment('line', 0, 1);
    fig.setFigureCollision(0, true);

    final decoded = Figure.fromJsonString(fig.exportToJson());

    expect(decoded.getFigureCollision(0), isTrue);
    expect(decoded.getFigureCollision(1), isFalse);

    // Toggle off removes the entry.
    decoded.setFigureCollision(0, false);
    expect(decoded.getFigureCollision(0), isFalse);
  });

test('figure colour override survives attach (join) and re-keying', () {
    final fig = Figure('AttachColor')
      ..points.addAll([
        Point2(0, 0), Point2(40, 0), // Figure A (root 0)
        Point2(0, -40), Point2(40, -40), // Figure B (root 2)
      ])
      ..rootIndices.addAll([0, 2]);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 2, 3);
    fig.setFigureColorOverride(2, 0.5, '#00ff00');

    // Attach B onto A: target point 1 becomes the attached joint first.
    fig.points[1].isAttached = true;
    final newTarget = fig.joinPoints(3, 1);

    expect(newTarget, 1);
    // B's points now resolve to the joint key (1); its colour must follow.
    final bSide = fig.figureKeyFor(2);
    expect(bSide, 1);
    expect(fig.getFigureColorOverride(bSide, 0.5), '#00ff00');

    // Detach: splitting at the joint boundary keeps the colour with B.
    final newRoot = fig.splitJoint(1, 2, 40, -40);
    expect(newRoot, greaterThan(2));
    expect(fig.getFigureColorOverride(newRoot, 0.5), '#00ff00');
  });

  test('attach dragging the figure ROOT keeps overrides keyed to that root', () {
    final fig = Figure('AttachRoot')
      ..points.addAll([
        Point2(0, 0), Point2(40, 0), // Figure A (root 0)
        Point2(0, -40), Point2(40, -40), // Figure B (root 2)
      ])
      ..rootIndices.addAll([0, 2]);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 2, 3);
    // Colour/collision live on B's ROOT pivot (point 2).
    fig.setFigureColorOverride(2, 0.5, '#0000ff');
    fig.setFigureCollision(2, true);

    // Attach by dragging B's root (the point the attach tool grabs) onto A's
    // point 1. movedIdx == 2 == the override key.
    fig.points[1].isAttached = true;
    final newTarget = fig.joinPoints(2, 1);

    expect(newTarget, 1);
    // B's surviving point (old 3 -> new 2) resolves to the joint key.
    expect(fig.figureKeyFor(2), 1);
    expect(fig.getFigureColorOverride(1, 0.5), '#0000ff');
    expect(fig.getFigureCollision(1), isTrue);
    // A's own state untouched.
    expect(fig.getFigureColorOverride(0, 0.5), isNull);
  });

  test('moveFigureOverrides keeps colour when a figure gains a new root', () {
    final fig = Figure('Move')
      ..points.addAll([Point2(0, 0), Point2(40, 0), Point2(0, -40)])
      ..rootIndices.add(0);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 1, 2);
    // Simulate an attached figure keyed to joint point 1.
    fig.points[1].isAttached = true;
    fig.setFigureColorOverride(1, 0.5, '#ff8800');
    fig.setFigureCollision(1, true);

    final newRoot = fig.addPoint(0, -40);
    fig.moveFigureOverrides(1, newRoot);

    expect(fig.getFigureColorOverride(newRoot, 0.5), '#ff8800');
    expect(fig.getFigureCollision(newRoot), isTrue);
    // Root figure is untouched.
    expect(fig.getFigureColorOverride(0, 0.5), isNull);
  });

  test('hex color helpers', () {
    final c = parseHexColor('#d1d5db');
    expect(c, isNotNull);
    expect(colorToHex(c), '#d1d5db');
    expect(parseHexColor(''), isNull);
    expect(parseHexColor('#abc'), isNotNull);
    final withAlpha = parseHexColor('#80d1d5db');
    expect(withAlpha, isNotNull);
    expect(colorToHex(withAlpha), '#80d1d5db');
    final roundTrip = parseHexColor(colorToHex(withAlpha));
    expect(roundTrip, isNotNull);
    expect(roundTrip!.a, closeTo(withAlpha!.a, 0.001));
  });

  test('joinPoints merges a point into a target and keeps the target root', () {
    final fig = Figure('J')
      ..points.addAll([Point2(0, 0), Point2(40, 0), Point2(80, 0)])
      ..rootIndices.addAll([0, 2]);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 1, 2);

    // Merge the leaf point 1 into target 0.
    final target = fig.joinPoints(1, 0);

    expect(target, 0);
    expect(fig.points.length, 2);
    expect(fig.segments.length, 2);
    // Both segments now reference the surviving points.
    expect(fig.segments.every((s) => s.point1Index < 2 && s.point2Index < 2), isTrue);
  });

  test('joinPoints removes the moved point root and keeps the target root', () {
    final fig = Figure('J2')
      ..points.addAll([Point2(0, 0), Point2(40, 0), Point2(80, 0)])
      ..rootIndices.addAll([0, 1]);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 1, 2);

    // movedIdx (1) is itself a root; after merging into 0 the root entry
    // for the moved point disappears and only the target root remains.
    final target = fig.joinPoints(1, 0);

    expect(target, 0);
    expect(fig.rootIndices, [0]);
  });

  test('splitJoint duplicates a shared point and gives the new point a root', () {
    final fig = Figure('U')
      ..points.addAll([Point2(0, 0), Point2(40, 0), Point2(80, 0)])
      ..rootIndices.add(0);
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 1, 2);

    // Split the joint (point 1) away from neighbour 0; the copy is placed at
    // (10, 10) and must become a new root.
    final newIdx = fig.splitJoint(1, 0, 10, 10);

    expect(newIdx, 3);
    expect(fig.points.length, 4);
    expect(fig.rootIndices, [0, 1]);
    // The detached segment (0,1) has its joint end re-pointed to the copy.
    final detached = fig.segments.singleWhere(
      (s) => s.point2Index == 3 || s.point1Index == 3,
    );
    expect(detached.point1Index, 0);
    expect(detached.point2Index, 3);
    // The other segment keeps the original joint point 1.
    expect(fig.segments.any((s) =>
        s.point1Index == 1 || s.point2Index == 1), isTrue);
  });

  test('joinPoints merging two separate figures leaves a single root', () {
    final fig = Figure('J3')
      ..points.addAll([Point2(0, 0), Point2(40, 0), Point2(100, 0), Point2(140, 0)])
      ..rootIndices.addAll([0, 2]);
    // Figure A: (0,1), Figure B: (2,3)
    fig.createSegment('line', 0, 1);
    fig.createSegment('line', 2, 3);

    // Drag Figure B's endpoint (3) onto Figure A's endpoint (1): the dragged
    // figure's root (2) must disappear; only the target's root (0) stays.
    final target = fig.joinPoints(3, 1);

    expect(target, 1);
    expect(fig.rootIndices, [0]);
    // repairRoots is idempotent: still exactly one root for the merged figure.
    fig.repairRoots();
    expect(fig.rootIndices.length, 1);
  });
}
