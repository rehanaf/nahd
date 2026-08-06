part of '../figure_canvas.dart';

extension _TransformTools on _FigureCanvasState {
  void handleTransformStart(Offset w, EditorTool tool, Figure fig, CameraTransform cam) {
    if (tool == EditorTool.rotate) {
      if (_handleRotateStart(w, fig)) return;
    }

    if (tool == EditorTool.stretch) {
      final ptHit = _hitTestPoint(w);
      if (ptHit < 0) {
        widget.controller.setSelectedPoint(null);
        widget.controller.setSelectedSegment(null);
        return;
      }
      widget.controller.setSelectedPoint(ptHit);
      final sf = _segmentTouching(fig, ptHit);
      widget.controller.setSelectedSegment(sf?.id);
      int root = ptHit;
      for (final r in fig.getFigureRoots()) {
        if (r >= 0 &&
            r < fig.points.length &&
            fig.connectedComponent(r).contains(ptHit)) {
          root = r;
          break;
        }
      }
      final rx = fig.points[root].x;
      final ry = fig.points[root].y;
      final comp = fig.connectedComponent(root).toList()..sort();
      final angles = <double>[];
      final dists = <double>[];
      for (final i in comp) {
        dists.add(math.sqrt(
            (fig.points[i].x - rx) * (fig.points[i].x - rx) +
                (fig.points[i].y - ry) * (fig.points[i].y - ry)));
        angles.add(
            math.atan2(fig.points[i].y - ry, fig.points[i].x - rx));
      }
      final startDist =
          math.sqrt((w.dx - rx) * (w.dx - rx) + (w.dy - ry) * (w.dy - ry));
      final origCtrl = <String, _Ctrl>{};
      for (final s in fig.segments) {
        if (s.curved && s.controlDX != null && s.controlDY != null) {
          origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
        }
      }
      _captureAnchorForPoint(fig, root, all: true);
      _drag
        ..reset()
        ..active = true
        ..isPoint = false
        ..stretching = true
        ..pivot = root
        ..connPts = comp
        ..initAngles = angles
        ..initDists = dists
        ..startDist = startDist > 0.001 ? startDist : 1
        ..fkCtrl = origCtrl
        ..startX = w.dx
        ..startY = w.dy;
      widget.controller.forceUpdate();
      return;
    }

    if (tool == EditorTool.rotateAll) {
      if (fig.points.length < 2) return;
      int root = 0;
      final selId = widget.controller.selectedSegmentId;
      if (selId != null) {
        final selSeg = fig.getSegment(selId);
        if (selSeg != null && selSeg.point1Index < fig.points.length) {
          root = _rootOfPoint(fig, selSeg.point1Index);
        }
      } else {
        final roots = fig.getFigureRoots();
        if (roots.isNotEmpty && roots.first < fig.points.length) {
          root = roots.first;
        }
      }
      final comp = fig.connectedComponent(root).toList()..sort();
      final cx = fig.points[root].x;
      final cy = fig.points[root].y;
      final ias = comp
          .map((i) => math.atan2(fig.points[i].y - cy, fig.points[i].x - cx))
          .toList();
      final ids = comp
          .map((i) => math.sqrt(
              (fig.points[i].x - cx) * (fig.points[i].x - cx) +
                  (fig.points[i].y - cy) * (fig.points[i].y - cy)))
          .toList();
      final origCtrl = <String, _Ctrl>{};
      for (final s in fig.segments) {
        if (s.curved && s.controlDX != null && s.controlDY != null) {
          origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
        }
      }
      _captureAnchorForPoint(fig, root, all: true);
      _drag
        ..reset()
        ..active = true
        ..rotating = true
        ..pivot = root
        ..connPts = comp
        ..initAngles = ias
        ..initDists = ids
        ..startAngle = math.atan2(w.dy - cy, w.dx - cx)
        ..startPtX = cx
        ..startPtY = cy
        ..fkCtrl = origCtrl;
      widget.controller.forceUpdate();
      return;
    }
  }
}
