part of '../figure_canvas.dart';

extension _CurveTool on _FigureCanvasState {
  void handleCurveStart(Offset w, EditorTool tool, Figure fig, CameraTransform cam) {
    if (tool == EditorTool.curve) {
      for (final s in fig.segments) {
        if (!s.curved || s.controlDX == null) continue;
        final mx = (fig.points[s.point1Index].x + fig.points[s.point2Index].x) /
            2;
        final my = (fig.points[s.point1Index].y + fig.points[s.point2Index].y) /
            2;
        final cx = mx + s.controlDX!;
        final cy = my + s.controlDY!;
        if (math.sqrt((w.dx - cx) * (w.dx - cx) + (w.dy - cy) * (w.dy - cy)) <
            12 / cam.zoom) {
          widget.controller.setSelectedSegment(s.id);
          _drag
            ..reset()
            ..active = true
            ..segId = s.id
            ..curving = true
            ..startX = w.dx
            ..startY = w.dy
            ..startPtX = s.controlDX!
            ..startPtY = s.controlDY!;
          return;
        }
      }
      final segHit = _hitTestSegment(w);
      if (segHit != null) {
        final seg = fig.getSegment(segHit);
        if (seg == null || seg.type != 'line') return;
        if (seg.curved && seg.controlDX != null) {
          seg.curved = false;
          seg.controlDX = null;
          seg.controlDY = null;
          widget.controller.setSelectedSegment(null);
          widget.controller.setSelectedPoint(null);
          widget.controller.forceUpdate();
          widget.controller.pushHistory();
          return;
        }
        seg.curved = true;
        seg.controlDX = 0;
        seg.controlDY = 0;
        widget.controller.setSelectedSegment(segHit);
        widget.controller.setSelectedPoint(null);
        _drag
          ..reset()
          ..active = true
          ..segId = segHit
          ..curving = true
          ..startX = w.dx
          ..startY = w.dy;
        widget.controller.forceUpdate();
        widget.controller.pushHistory();
        return;
      }
    }
  }
}
