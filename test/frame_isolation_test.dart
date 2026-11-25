import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/models/figure.dart';
import 'package:id_animate/core/models/figure_animation.dart';
import 'package:id_animate/core/project_storage.dart';
import 'package:id_animate/features/editor/controllers/editor_controller.dart';

EditorController _controller(Figure fig) {
  return EditorController(
    editorMode: EditorMode.animate,
    projectType: ProjectType.animation,
    initialFigure: fig,
    initialAnimation: FigureAnimation()..duration = 20,
  );
}

Figure _oneLine() {
  final fig = Figure();
  final p1 = fig.addPoint(0, 0);
  final p2 = fig.addPoint(100, 0);
  fig.createSegment('line', p1, p2);
  fig.rootIndices = [p1];
  return fig;
}

void main() {
  group('frame isolation', () {
    test('editing earlier frame does not leak into later authored frame', () {
      final fig = _oneLine();
      final c = _controller(fig);
      final seg = c.figure.segments.first;
      final p1 = c.figure.rootIndices.first;

      // Author frame 10 with a point pose.
      c.setCurrentTime(10);
      c.recordPointPose(p1, 10, 10);
      c.recordPointPose(seg.point2Index, 110, 10);
      final p1At10 = c.currentAnimation!.getTrack(p1)!.getValue(10)!.x;
      final colorAt10 = seg.color;

      // Go back to frame 4 and change point + color.
      c.setCurrentTime(4);
      c.recordPointPose(p1, 44, 44);
      c.recordFrameValue('seg:${seg.id}:color', seg.color, '#FF0000');

      // Frame 10 must keep its old state.
      expect(c.currentAnimation!.getTrack(p1)!.getValue(10)!.x, p1At10);
      expect(
        c.figure.styleFor(seg, 10, enabled: true).color,
        colorAt10,
      );
      // Frame 4 must have the new state.
      expect(c.currentAnimation!.getTrack(p1)!.getValue(4)!.x, 44);
      expect(
        c.figure.styleFor(seg, 4, enabled: true).color,
        '#FF0000',
      );
    });

    test('adding object at earlier frame does not appear at later authored frame', () {
      final fig = _oneLine();
      final c = _controller(fig);
      final originalCount = c.figure.segments.length;

      c.setCurrentTime(10);
      c.recordPointPose(c.figure.rootIndices.first, 5, 5);

      c.setCurrentTime(4);
      c.addSegment('line');

      expect(c.figure.segments.length, originalCount + 1);
      final newSeg = c.figure.segments.last;
      expect(c.figure.styleFor(newSeg, 4, enabled: true).hidden, isFalse);
      expect(c.figure.styleFor(newSeg, 10, enabled: true).hidden, isTrue);
    });
  });
}