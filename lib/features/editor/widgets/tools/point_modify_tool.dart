part of '../figure_canvas.dart';

extension _PointModifyTool on _FigureCanvasState {
  void handlePointModifyStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.point) {
      final ptHit = _hitTestPoint(w);
      if (ptHit >= 0) {
        widget.controller.setSelectedPoint(ptHit);
        final cs = _segmentTouching(fig, ptHit);
        widget.controller.setSelectedSegment(cs?.id);
        final moving = <int>[ptHit, ...fig.childPoints(ptHit)];
        final init = <int, Point2>{};
        for (final i in moving) {
          init[i] = fig.points[i].clone();
        }
        _drag
          ..reset()
          ..active = true
          ..isPoint = true
          ..ptIdx = ptHit
          ..startX = w.dx
          ..startY = w.dy
          ..startPtX = fig.points[ptHit].x
          ..startPtY = fig.points[ptHit].y
          ..connPts = moving
          ..fkInit = init;
        _captureAnchorForPoint(fig, ptHit);
        widget.controller.forceUpdate();
        return;
      }
    }

    if (tool == EditorTool.modify) {
      final ptHit = _hitTestPoint(w);
      if (ptHit >= 0) {
        widget.controller.setSelectedPoint(ptHit);
        final cs = _segmentTouching(fig, ptHit);
        widget.controller.setSelectedSegment(cs?.id);
        _drag
          ..reset()
          ..active = true
          ..isPoint = true
          ..ptIdx = ptHit
          ..startX = w.dx
          ..startY = w.dy
          ..startPtX = fig.points[ptHit].x
          ..startPtY = fig.points[ptHit].y;
        _captureAnchorForPoint(fig, ptHit, all: true);
        return;
      }
    }
  }
}
