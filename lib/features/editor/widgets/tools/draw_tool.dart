part of '../figure_canvas.dart';

extension _DrawTool on _FigureCanvasState {
  void handleDrawStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.line || tool == EditorTool.circle) {
      final ptHit = _hitTestPoint(w);
      if (ptHit < 0) {
        if (fig.points.isEmpty) {
          final idx = fig.addPoint(w.dx, w.dy);
          _lastPt = idx;
          widget.controller.forceUpdate();
        }
        return;
      }
      final last = _lastPt;
      final alreadyConnected = last != null &&
          fig.segments.any((s) =>
              (s.point1Index == last && s.point2Index == ptHit) ||
              (s.point1Index == ptHit && s.point2Index == last));
      if (last != null && last != ptHit && !alreadyConnected) {
        final seg = fig.createSegment(tool.name, last, ptHit);
        widget.controller.setSelectedSegment(seg.id);
        widget.controller.setSelectedPoint(ptHit);
        _lastPt = ptHit;
        widget.controller.forceUpdate();
        widget.controller.pushHistory();
        return;
      }
      final p2 = fig.addPoint(w.dx, w.dy);
      final seg = fig.createSegment(tool.name, ptHit, p2);
      _lastPt = p2;
      widget.controller.setSelectedSegment(seg.id);
      widget.controller.setSelectedPoint(p2);
      _drag
        ..reset()
        ..active = true
        ..isPoint = true
        ..ptIdx = p2
        ..creating = true
        ..startX = w.dx
        ..startY = w.dy
        ..startPtX = w.dx
        ..startPtY = w.dy
        ..anchorX = fig.points[ptHit].x
        ..anchorY = fig.points[ptHit].y;
      widget.controller.forceUpdate();
      return;
    }
  }
}
