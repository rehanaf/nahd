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

  bool _handleRotateStart(Offset w, Figure fig) {
    final ptHit = _hitTestPoint(w);
    if (ptHit < 0) {
      widget.controller.setSelectedPoint(null);
      widget.controller.setSelectedSegment(null);
      return false;
    }
    widget.controller.setSelectedPoint(ptHit);
    final seg = _segmentTouching(fig, ptHit);
    widget.controller.setSelectedSegment(seg?.id);

    final comp = fig.connectedComponent(ptHit);
    if (comp.length < 2) {
      widget.controller.forceUpdate();
      return false;
    }
    final adj = <int, List<int>>{};
    for (final i in comp) {
      adj[i] = [];
    }
    var edgeCount = 0;
    for (final s in fig.segments) {
      if (!comp.contains(s.point1Index) || !comp.contains(s.point2Index)) {
        continue;
      }
      adj[s.point1Index]!.add(s.point2Index);
      adj[s.point2Index]!.add(s.point1Index);
      edgeCount++;
    }

    final isCycle = edgeCount >= comp.length;

    int centre;
    List<int> rotPts;
    if (isCycle) {
      final allRoots = fig.getFigureRoots();
      final depth = <int, int>{};
      final queue = <int>[];
      for (final r in allRoots) {
        if (r < 0 || r >= fig.points.length) continue;
        depth[r] = 0;
        queue.add(r);
      }
      while (queue.isNotEmpty) {
        final cur = queue.removeAt(0);
        for (final other in adj[cur]!) {
          if (depth.containsKey(other)) continue;
          depth[other] = depth[cur]! + 1;
          queue.add(other);
        }
      }
      int pivotNode = ptHit;
      var bestDepth = depth[ptHit] ?? 0;
      for (final i in comp) {
        final d = depth[i];
        if (d == null || allRoots.contains(i)) continue;
        if (d < bestDepth) {
          bestDepth = d;
          pivotNode = i;
        }
      }
      centre = ptHit == pivotNode
          ? (seg != null
              ? (seg.point1Index == ptHit ? seg.point2Index : seg.point1Index)
              : (adj[ptHit]!.isNotEmpty ? adj[ptHit]!.first : ptHit))
          : pivotNode;
      rotPts = comp.where((i) => !allRoots.contains(i)).toList();
    } else {
      final allRoots = fig.getFigureRoots();
      final parent = <int, int>{};
      final visited = <int>{};
      final queue = <int>[];
      for (final r in allRoots) {
        if (r < 0 || r >= fig.points.length) continue;
        visited.add(r);
        queue.add(r);
      }
      while (queue.isNotEmpty) {
        final cur = queue.removeAt(0);
        for (final other in adj[cur]!) {
          if (visited.contains(other)) continue;
          visited.add(other);
          parent[other] = cur;
          queue.add(other);
        }
      }
      centre = parent[ptHit] ?? (seg?.point1Index == ptHit ? seg!.point2Index : seg!.point1Index);
      final rot = <int>[];
      final stk = <int>[ptHit];
      while (stk.isNotEmpty) {
        final cur = stk.removeLast();
        if (rot.contains(cur)) continue;
        rot.add(cur);
        for (final other in adj[cur]!) {
          if (parent[other] == cur) stk.add(other);
        }
      }
      rotPts = rot;
    }
    if (rotPts.isEmpty || centre < 0 || centre >= fig.points.length) {
      widget.controller.forceUpdate();
      return false;
    }
    final px = fig.points[centre].x;
    final py = fig.points[centre].y;
    final ias = rotPts
        .map((i) => math.atan2(fig.points[i].y - py, fig.points[i].x - px))
        .toList();
    final ids = rotPts
        .map((i) => math.sqrt((fig.points[i].x - px) * (fig.points[i].x - px) +
            (fig.points[i].y - py) * (fig.points[i].y - py)))
        .toList();
    final origCtrl = <String, _Ctrl>{};
    for (final s in fig.segments) {
      if (s.curved && s.controlDX != null && s.controlDY != null) {
        origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
      }
    }
    _captureAnchorForPoint(fig, ptHit, all: true);
    _drag
      ..reset()
      ..active = true
      ..rotating = true
      ..pivot = centre
      ..connPts = rotPts
      ..initAngles = ias
      ..initDists = ids
      ..startAngle = math.atan2(w.dy - py, w.dx - px)
      ..startPtX = px
      ..startPtY = py
      ..fkCtrl = origCtrl;
    widget.controller.forceUpdate();
    return true;
  }
}
