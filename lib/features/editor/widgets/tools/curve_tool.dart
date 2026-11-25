part of '../figure_canvas.dart';

extension _CurveTool on _FigureCanvasState {
  void handleCurveStart(Offset w, EditorTool tool, Figure fig, CameraTransform cam) {
    if (tool == EditorTool.curve) {
      for (final s in fig.segments) {
        final style = fig.styleFor(s, widget.controller.currentTime,
            enabled: widget.controller.isAnimateMode);
        if (!style.curved || style.controlDX == null || style.controlDY == null) {
          continue;
        }
        final mx = (fig.points[s.point1Index].x + fig.points[s.point2Index].x) /
            2;
        final my = (fig.points[s.point1Index].y + fig.points[s.point2Index].y) /
            2;
        final cx = mx + style.controlDX!;
        final cy = my + style.controlDY!;
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
            ..startPtX = style.controlDX!
            ..startPtY = style.controlDY!;
          return;
        }
      }
      final segHit = _hitTestSegment(w);
      if (segHit != null) {
        final seg = fig.getSegment(segHit);
        if (seg == null || seg.type != 'line') return;
        final style = fig.styleFor(seg, widget.controller.currentTime,
            enabled: widget.controller.isAnimateMode);
        if (style.curved) {
          widget.controller.recordSegmentValue(
              seg, 'curved', style.curved, false);
          widget.controller.recordSegmentValue(
              seg, 'controlDX', style.controlDX, null);
          widget.controller.recordSegmentValue(
              seg, 'controlDY', style.controlDY, null);
          seg.curved = false;
          seg.controlDX = null;
          seg.controlDY = null;
          widget.controller.setSelectedSegment(null);
          widget.controller.setSelectedPoint(null);
          widget.controller.forceUpdate();
          widget.controller.pushHistory();
          return;
        }
        widget.controller.recordSegmentValue(seg, 'curved', style.curved, true);
        widget.controller.recordSegmentValue(
            seg, 'controlDX', style.controlDX, 0.0);
        widget.controller.recordSegmentValue(
            seg, 'controlDY', style.controlDY, 0.0);
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
