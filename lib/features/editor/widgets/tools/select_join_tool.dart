part of '../figure_canvas.dart';

extension _SelectJoinTool on _FigureCanvasState {
  void handleSelectJoinStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.join) {
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
        widget.controller.forceUpdate();
        return;
      }
    }

    if (tool != EditorTool.line &&
        tool != EditorTool.circle &&
        tool != EditorTool.image &&
        tool != EditorTool.none) {
      final rootHit = _hitTestPoint(w);
      final roots = fig.rootIndices.isNotEmpty ? fig.rootIndices : [0];
      if (roots.contains(rootHit)) {
        final allC = _findConnectedPoints(fig, rootHit)..add(rootHit);
        final init = <int, Point2>{};
        for (final i in allC) {
          init[i] = fig.points[i].clone();
        }
        widget.controller.setSelectedPoint(rootHit);
        final cs = _segmentTouching(fig, rootHit);
        widget.controller.setSelectedSegment(cs?.id);
        _drag
          ..reset()
          ..active = true
          ..isPoint = true
          ..ptIdx = rootHit
          ..startX = w.dx
          ..startY = w.dy
          ..startPtX = fig.points[rootHit].x
          ..startPtY = fig.points[rootHit].y
          ..connPts = allC
          ..fkInit = init;
        widget.controller.forceUpdate();
        return;
      }
    }

    if (tool == EditorTool.select) {
      final ptHit = _hitTestPoint(w);
      if (ptHit >= 0) {
        final allC = _findConnectedPoints(fig, ptHit)..add(ptHit);
        widget.controller.setSelectedPoint(ptHit);
        final cs = _segmentTouching(fig, ptHit);
        widget.controller.setSelectedSegment(cs?.id);
        final init = <int, Point2>{};
        for (final i in allC) {
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
          ..connPts = allC
          ..fkInit = init;
        _captureAnchorForPoint(fig, ptHit, all: true);
        widget.controller.forceUpdate();
        return;
      }
      widget.controller.setSelectedPoint(null);
      final segHit = _hitTestSegment(w);
      widget.controller.setSelectedSegment(segHit);
    }
  }

  void handleSelectJoinMove(Figure fig, _DragState d, Offset w) {
    if (widget.controller.activeTool == EditorTool.join &&
        d.isPoint &&
        d.ptIdx >= 0 &&
        d.ptIdx < fig.points.length &&
        !d.jointDone) {
      _handleJoinMove(fig, d, w);
    }
  }
}
