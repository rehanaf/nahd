import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/models/figure.dart';
import 'package:id_animate/core/models/figure_animation.dart';
import 'package:id_animate/core/project_storage.dart';
import 'package:id_animate/features/editor/controllers/editor_controller.dart';

EditorController _animationController(Figure fig) {
  return EditorController(
    editorMode: EditorMode.animate,
    projectType: ProjectType.animation,
    initialFigure: fig,
    initialAnimation: FigureAnimation()..duration = 20,
  );
}

Figure _twoObjects() {
  final fig = Figure();
  final a0 = fig.addPoint(0, 0);
  final a1 = fig.addPoint(100, 0);
  final b0 = fig.addPoint(0, 200);
  final b1 = fig.addPoint(100, 200);
  final a = fig.createSegment('line', a0, a1);
  fig.createSegment('line', b0, b1);
  fig.rootIndices = [a0, b0];
  fig.setFrameOverride('seg:${a.id}:color', '#FF0000', 0);
  return fig;
}

void main() {
  group('animation mode (separate from preset)', () {
    test('delete hides from current frame onward, earlier frames keep object', () {
      final fig = _twoObjects();
      final c = _animationController(fig);
      final root = c.figure.rootIndices.first;
      c.setCurrentTime(6);

      c.hideFigureAtCurrentFrame(root);

      expect(c.figure.getFigureVisibility(root, 0), isTrue);
      expect(c.figure.getFigureVisibility(root, 5), isTrue);
      expect(c.figure.getFigureVisibility(root, 6), isFalse);
      expect(c.figure.getFigureVisibility(root, 19), isFalse);
      // A hide never removes the object structurally.
      expect(c.figure.segments.length, 2);
      expect(c.figure.points.length, 4);
    });

    test('re-create at a later frame makes a new object with fresh ids', () {
      final fig = _twoObjects();
      final c = _animationController(fig);
      final originalRoot = c.figure.rootIndices.first;
      final originalIds = c.figure.segments.map((s) => s.id).toSet();
      c.setCurrentTime(6);
      c.hideFigureAtCurrentFrame(originalRoot);
      c.setCurrentTime(12);

      final newPoints = c.recreateFigureAtCurrentFrame(originalRoot);

      expect(newPoints, isNotNull);
      expect(c.figure.points.length, greaterThan(4));
      final newIds = c.figure.segments
          .map((s) => s.id)
          .where((id) => !originalIds.contains(id))
          .toSet();
      expect(newIds, isNotEmpty);
      expect(newIds.intersection(originalIds), isEmpty);

      final newRoot = c.figure.figureKeyFor(newPoints!.first);
      expect(c.figure.getFigureVisibility(newRoot, 11), isFalse);
      expect(c.figure.getFigureVisibility(newRoot, 12), isTrue);
      // Original stays hidden from frame 6 onward.
      expect(c.figure.getFigureVisibility(originalRoot, 12), isFalse);

      // The copy has its own pose keyframe at the re-created frame.
      final track = c.currentAnimation!.tracks
          .firstWhere((t) => t.pointIndex == newPoints.first);
      expect(track.getValue(12), isNotNull);
    });

    test('extractSubFigure remaps overrides and does not share ids', () {
      final fig = _twoObjects();
      final seg = fig.segments.first;
      fig.captureFrameOverride('seg:${seg.id}:hidden', false);
      fig.setFrameOverride('seg:${seg.id}:hidden', true, 4);

      final sub = fig.extractSubFigure(fig.connectedComponent(fig.rootIndices.first));

      expect(sub.segments.length, 1);
      expect(sub.points.length, 2);
      expect(sub.segments.first.id, isNot(seg.id));
      expect(
        sub.frameOverrides.values
            .expand((values) => values.keys)
            .any((key) => key.toString().contains(seg.id)),
        isFalse,
      );
      expect(
        sub.frameOverrides.values
            .expand((values) => values.keys)
            .any((key) => key.toString().contains(sub.segments.first.id)),
        isTrue,
      );
      expect(fig.segments.length, 2, reason: 'source is untouched');
    });

    test('preset import seeds visibility and pose at the current frame', () {
      final src = _twoObjects();
      final c = _animationController(Figure());
      c.setCurrentTime(7);

      final newPoints = c.mergeImportedFigure(src);

      expect(newPoints.length, 4);
      final newRoot = c.figure.figureKeyFor(newPoints.first);
      expect(c.figure.getFigureVisibility(newRoot, 6), isFalse);
      expect(c.figure.getFigureVisibility(newRoot, 7), isTrue);
      expect(
        c.currentAnimation!.tracks
            .firstWhere((t) => t.pointIndex == newPoints.first)
            .getValue(7),
        isNotNull,
      );
    });
  });
}
