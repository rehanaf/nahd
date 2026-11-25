import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/lottie_export.dart';
import 'package:id_animate/core/models/figure.dart';
import 'package:id_animate/core/models/figure_animation.dart';
import 'package:id_animate/core/project_storage.dart';
import 'package:id_animate/features/editor/controllers/editor_controller.dart';

EditorController _controller(Figure fig, {double duration = 10}) {
  return EditorController(
    editorMode: EditorMode.animate,
    projectType: ProjectType.preset,
    initialFigure: fig,
    initialAnimation: FigureAnimation()..duration = duration,
  );
}

void main() {
  group('per-frame overrides', () {
    test('capture + set produce a hard step at the edited frame', () {
      final fig = Figure();
      final seg = fig.addSegment('line');
      final key = 'seg:${seg.id}:width';
      final original = seg.width;

      fig.captureFrameOverride(key, original);
      seg.width = 12;
      fig.setFrameOverride(key, seg.width, 8);

      expect(fig.styleFor(seg, 0).width, original);
      expect(fig.styleFor(seg, 7).width, original);
      expect(fig.styleFor(seg, 8).width, 12);
      expect(fig.styleFor(seg, 30).width, 12);
    });

    test('styleFor(enabled: false) ignores overrides', () {
      final fig = Figure();
      final seg = fig.addSegment('line');
      fig.setFrameOverride('seg:${seg.id}:hidden', true, 4);
      seg.hidden = false;

      expect(fig.styleFor(seg, 5).hidden, isTrue);
      expect(fig.styleFor(seg, 5, enabled: false).hidden, isFalse);
    });

    test('nullable properties can be overridden to null', () {
      final fig = Figure();
      final seg = fig.addSegment('line')
        ..curved = true
        ..controlDX = 25;
      final key = 'seg:${seg.id}:controlDX';

      fig.captureFrameOverride(key, seg.controlDX);
      seg.controlDX = null;
      fig.setFrameOverride(key, null, 6);

      expect(fig.styleFor(seg, 5).controlDX, 25);
      expect(fig.styleFor(seg, 6).controlDX, isNull);
      expect(fig.frameNullableDouble(key, 20, 99), isNull);
      expect(fig.frameNullableDouble('never/set', 20, 99), 99);
    });

    test('text overrides are applied per frame', () {
      final fig = Figure();
      final seg = fig.addSegment('text')
        ..text = 'Old';
      final key = 'seg:${seg.id}:text';

      fig.captureFrameOverride(key, seg.text);
      seg.text = 'New';
      fig.setFrameOverride(key, seg.text, 10);

      expect(fig.styleFor(seg, 0).text, 'Old');
      expect(fig.styleFor(seg, 9).text, 'Old');
      expect(fig.styleFor(seg, 10).text, 'New');
    });

    test('overrides survive clone and JSON round-trip', () {
      final fig = Figure();
      final seg = fig.addSegment('circle');
      fig.captureFrameOverride('seg:${seg.id}:filled', seg.filled);
      seg.filled = false;
      fig.setFrameOverride('seg:${seg.id}:filled', false, 3);

      final clone = fig.clone();
      expect(clone.styleFor(clone.segments.first, 4).filled, isFalse);

      final restored = Figure.fromJsonString(fig.exportToJson());
      expect(restored.frameOverrides.keys, contains(0.0));
      expect(restored.frameOverrides.keys, contains(3.0));
      expect(restored.styleFor(restored.segments.first, 4).filled, isFalse);
    });

    test('draw order follows per-frame layer overrides', () {
      final fig = Figure();
      final a = fig.addSegment('line');
      final b = fig.addSegment('line');
      expect(fig.segmentsInDrawOrder().map((s) => s.id), [a.id, b.id]);

      fig.setFrameOverride('seg:${a.id}:layer', 5, 2);
      expect(fig.segmentsInDrawOrder(1).map((s) => s.id), [a.id, b.id]);
      expect(fig.segmentsInDrawOrder(3).map((s) => s.id), [b.id, a.id]);
    });

    test('controller color change at frame 5 only affects frame 5+', () {
      final fig = Figure();
      final seg = fig.addSegment('line');
      final c = _controller(fig);
      c.setCurrentTime(5);

      final style =
          c.figure.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
      final oldColor = style.color;
      c.recordSegmentValue(seg, 'color', oldColor, '#FF0000');
      seg.color = '#FF0000';

      expect(c.figure.styleFor(seg, 0).color, oldColor);
      expect(c.figure.styleFor(seg, 4).color, oldColor);
      expect(c.figure.styleFor(seg, 5).color, '#FF0000');
      expect(c.figure.styleFor(seg, 9).color, '#FF0000');
    });

    test('curve toggle on one segment does not affect another', () {
      final fig = Figure();
      final a = fig.addSegment('line');
      final b = fig.addSegment('line');
      final c = _controller(fig);
      c.setCurrentTime(5);

      final style =
          c.figure.styleFor(a, c.currentTime, enabled: c.isAnimateMode);
      c.recordSegmentValue(a, 'curved', style.curved, true);
      c.recordSegmentValue(a, 'controlDX', style.controlDX, 0.0);
      c.recordSegmentValue(a, 'controlDY', style.controlDY, 0.0);
      a
        ..curved = true
        ..controlDX = 0
        ..controlDY = 0;

      expect(c.figure.styleFor(a, 0).curved, isFalse);
      expect(c.figure.styleFor(a, 5).curved, isTrue);
      expect(c.figure.styleFor(b, 5).curved, isFalse);
      expect(c.figure.styleFor(b, 0).curved, isFalse);
    });

    test('importing the same figure twice gives each copy unique ids', () {
      final c = _controller(Figure());
      final src = Figure();
      src.addSegment('line');
      src.addSegment('line');
      final originalIds = src.segments.map((s) => s.id).toList();

      c.mergeImportedFigure(src);
      c.mergeImportedFigure(src);

      final ids = c.figure.segments.map((s) => s.id).toList();
      expect(ids.length, 4);
      expect(ids.toSet().length, 4, reason: 'no duplicate segment ids');
      expect(ids.any(originalIds.contains), isFalse,
          reason: 'imported copies must not reuse source ids');
    });

    test('controller revision increments on every notify', () {
      final c = _controller(Figure());
      final before = c.revision;
      c.setCurrentTime(3);
      expect(c.revision, greaterThan(before));
      final after = c.revision;
      c.forceUpdate();
      expect(c.revision, greaterThan(after));
    });
  });

  group('join / attach keyframes', () {
    test('splitJoint records the new point pose at the current frame', () {
      final fig = Figure();
      final p0 = fig.addPoint(0, 0);
      final p1 = fig.addPoint(100, 0);
      fig.createSegment('line', p0, p1);
      fig.rootIndices = [p0];
      final c = _controller(fig);
      c.setCurrentTime(4);

      final newIdx = c.splitJoint(p1, p0, 120, 30);

      expect(newIdx, isNotNull);
      final track = c.currentAnimation!.tracks
          .firstWhere((t) => t.pointIndex == newIdx);
      expect(track.getValue(4)!.x, 120);
      expect(track.getValue(4)!.y, 30);
      expect(fig.points[newIdx!].x, 120);
    });

    test('joinPoints removes the dragged track and keys the survivor', () {
      final fig = Figure();
      final p0 = fig.addPoint(0, 0);
      final p1 = fig.addPoint(100, 0);
      final p2 = fig.addPoint(200, 0);
      fig.createSegment('line', p0, p1);
      fig.createSegment('line', p1, p2);
      fig.rootIndices = [p0];
      final c = _controller(fig);
      c.setCurrentTime(6);
      c.recordPointsAtCurrentFrame([p0, p1, p2]);

      final joint = c.joinPoints(p2, p1);
      c.recordPointsAtCurrentFrame([joint]);

      expect(joint, p1);
      final indices = c.currentAnimation!.tracks.map((t) => t.pointIndex);
      expect(indices, isNot(contains(p2)));
      expect(indices, contains(joint));
      expect(
        c.currentAnimation!.tracks
            .firstWhere((t) => t.pointIndex == joint)
            .getValue(6),
        isNotNull,
      );
    });

    test('detached root gets a keyframe even without a follow-up drag', () {
      final fig = Figure();
      final p0 = fig.addPoint(0, 0);
      fig.addPoint(100, 0);
      fig.addPoint(100, 50);
      fig.addPoint(150, 50);
      fig.createSegment('line', p0, 1);
      fig.createSegment('line', 1, 2);
      final segC = fig.createSegment('line', 3, 4);
      fig.rootIndices = [p0, 3];
      fig.points[1].isAttached = true;
      final joint = fig.joinPoints(3, 1);
      fig.setAttachedSegments(joint, [segC.id]);
      final c = _controller(fig);
      c.setCurrentTime(3);

      final detached = fig.detachAttachedAt(1);
      expect(detached, isNotNull);
      c.recordPointsAtCurrentFrame([...detached!.pointIndices, detached.newRoot]);

      final track = c.currentAnimation!.tracks
          .firstWhere((t) => t.pointIndex == detached.newRoot);
      expect(track.getValue(3)!.x, fig.points[detached.newRoot].x);
      expect(track.getValue(3)!.y, fig.points[detached.newRoot].y);
    });
  });

  group('Lottie export', () {
    test('per-frame hide becomes animated opacity', () async {
      final fig = Figure();
      final seg = fig.addSegment('line');
      fig.captureFrameOverride('seg:${seg.id}:hidden', false);
      fig.setFrameOverride('seg:${seg.id}:hidden', true, 5);

      final anim = FigureAnimation()..duration = 10;
      final doc = jsonDecode(await exportLottieJson(fig, anim));
      final layers = doc['layers'] as List;
      expect(layers, isNotEmpty);
      final opacity = layers.first['ks']['o'];
      expect(opacity['a'], 1);
      final times = (opacity['k'] as List).map((k) => k['t']).toList();
      expect(times, contains(4));
      expect(times, contains(5));
    });

    test('override-aware shape width is exported', () async {
      final fig = Figure();
      final seg = fig.addSegment('line');
      fig.captureFrameOverride('seg:${seg.id}:width', seg.width);
      seg.width = 20;
      fig.setFrameOverride('seg:${seg.id}:width', 20.0, 3);

      final anim = FigureAnimation()..duration = 8;
      final doc = jsonDecode(await exportLottieJson(fig, anim));
      final layer = (doc['layers'] as List).first;
      final shape = (layer['shapes'] as List).first;
      final stroke =
          (shape['it'] as List).firstWhere((item) => item['ty'] == 'st');
      final width = stroke['w'];
      expect(width['a'], 1);
      expect((width['k'] as List).any((k) => k['s'].first == 20), isTrue);
    });
  });
}
