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
      // Multi-select stretch: scales the whole selected set around the grabbed
      // point (fixed pivot), including segment widths between selected points.
      final multiSel = widget.controller.multiSelection;
      if (multiSel.length > 1 && multiSel.contains(ptHit)) {
        widget.controller.setSelectedPoint(ptHit);
        final msf = _segmentTouching(fig, ptHit);
        widget.controller.setSelectedSegment(msf?.id);
        final set = multiSel.toList();
        final mx = fig.points[ptHit].x;
        final my = fig.points[ptHit].y;
        final origCtrl = <String, _Ctrl>{};
        final origSegs = <String, _SegInitial>{};
        for (final s in fig.segments) {
          if (s.curved && s.controlDX != null && s.controlDY != null) {
            origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
          }
          if (multiSel.contains(s.point1Index) &&
              multiSel.contains(s.point2Index)) {
            double iw = 100.0;
            if (s.imageWidth is num) iw = (s.imageWidth as num).toDouble();
            double ih = 100.0;
            if (s.imageHeight is num) ih = (s.imageHeight as num).toDouble();
            origSegs[s.id] =
                _SegInitial(width: s.width, imageWidth: iw, imageHeight: ih);
          }
        }
        final startDist =
            math.sqrt((w.dx - mx) * (w.dx - mx) + (w.dy - my) * (w.dy - my));
        _captureAnchorForPoint(fig, ptHit, all: true);
        _drag
          ..reset()
          ..active = true
          ..isPoint = false
          ..stretching = true
          ..pivot = ptHit
          ..connPts = set
          ..initAngles = set
              .map((i) => math.atan2(fig.points[i].y - my, fig.points[i].x - mx))
              .toList()
          ..initDists = set
              .map((i) => math.sqrt(
                  (fig.points[i].x - mx) * (fig.points[i].x - mx) +
                      (fig.points[i].y - my) * (fig.points[i].y - my)))
              .toList()
          ..startDist = startDist > 0.001 ? startDist : 1
          ..fkCtrl = origCtrl
          ..initSegs.addAll(origSegs)
          ..startX = w.dx
          ..startY = w.dy;
        widget.controller.forceUpdate();
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
      final origSegs = <String, _SegInitial>{};
      for (final s in fig.segments) {
        if (s.curved && s.controlDX != null && s.controlDY != null) {
          origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
        }
        if (comp.contains(s.point1Index) && comp.contains(s.point2Index)) {
          double iw = 100.0;
          if (s.imageWidth is num) {
            iw = (s.imageWidth as num).toDouble();
          }
          double ih = 100.0;
          if (s.imageHeight is num) {
            ih = (s.imageHeight as num).toDouble();
          }
          origSegs[s.id] = _SegInitial(
            width: s.width,
            imageWidth: iw,
            imageHeight: ih,
          );
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
        ..initSegs.addAll(origSegs)
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
    var ptHit = _hitTestPoint(w);
    if (ptHit < 0) {
      widget.controller.setSelectedPoint(null);
      widget.controller.setSelectedSegment(null);
      return false;
    }

    final subRoot = _rootOfPoint(fig, ptHit);

    // Multi-select pivot rotate: dragging any selected point turns the whole
    // selection set about that point, overriding the single-figure rules.
    final multiSel = widget.controller.multiSelection;
    if (multiSel.length > 1 && multiSel.contains(ptHit)) {
      widget.controller.setSelectedPoint(ptHit);
      final mseg = _segmentTouching(fig, ptHit);
      widget.controller.setSelectedSegment(mseg?.id);
      final set = multiSel.toList();
      final mx = fig.points[ptHit].x;
      final my = fig.points[ptHit].y;
      final origCtrl = <String, _Ctrl>{};
      for (final s in fig.segments) {
        if (!s.curved || s.controlDX == null || s.controlDY == null) continue;
        if (multiSel.contains(s.point1Index) ||
            multiSel.contains(s.point2Index)) {
          origCtrl[s.id] = _Ctrl(s.controlDX!, s.controlDY!);
        }
      }
      _captureAnchorForPoint(fig, ptHit, all: true);
      _drag
        ..reset()
        ..active = true
        ..rotating = true
        ..pivot = ptHit
        ..connPts = set
        ..initAngles = set
            .map((i) => math.atan2(fig.points[i].y - my, fig.points[i].x - mx))
            .toList()
        ..initDists = set
            .map((i) => math.sqrt(
                (fig.points[i].x - mx) * (fig.points[i].x - mx) +
                    (fig.points[i].y - my) * (fig.points[i].y - my)))
            .toList()
        ..startAngle = math.atan2(w.dy - my, w.dx - mx)
        ..startPtX = mx
        ..startPtY = my
        ..fkCtrl = origCtrl;
      widget.controller.forceUpdate();
      return true;
    }

    // 1. Root points should NEVER rotate.
    if (ptHit == subRoot) {
      return false;
    }

    widget.controller.setSelectedPoint(ptHit);
    var seg = _segmentTouching(fig, ptHit);
    widget.controller.setSelectedSegment(seg?.id);

    final comp = fig.connectedComponent(ptHit);
    if (comp.length < 2) {
      widget.controller.forceUpdate();
      return false;
    }

    // Build adjacency
    final adj = <int, List<int>>{};
    for (final i in comp) {
      adj[i] = [];
    }
    for (final s in fig.segments) {
      if (!comp.contains(s.point1Index) || !comp.contains(s.point2Index)) {
        continue;
      }
      adj[s.point1Index]!.add(s.point2Index);
      adj[s.point2Index]!.add(s.point1Index);
    }

    // Spanning tree from subRoot to know depths and parents.
    final parent = <int, int>{};
    final depth = <int, int>{subRoot: 0};
    final queue = <int>[subRoot];
    final visitedBFS = <int>{subRoot};
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      for (final other in adj[cur]!) {
        if (visitedBFS.contains(other)) continue;
        visitedBFS.add(other);
        parent[other] = cur;
        depth[other] = depth[cur]! + 1;
        queue.add(other);
      }
    }

    // A static (locked) point is inert: grabbing it behaves exactly like
    // grabbing its nearest non-static ancestor. For 0 -> a -> b with b static,
    // dragging b must rotate a instead (as if a were dragged), and if a is
    // static too it keeps climbing towards the root.
    if (widget.controller.isPointStatic(ptHit)) {
      var grab = ptHit;
      while (widget.controller.isPointStatic(grab)) {
        if (grab == subRoot) {
          // Every ancestor up to the root is static: nothing may rotate.
          widget.controller.forceUpdate();
          return false;
        }
        grab = parent[grab]!;
      }
      final remapped = _segmentTouching(fig, grab);
      widget.controller.setSelectedPoint(grab);
      widget.controller.setSelectedSegment(remapped?.id);
      seg = remapped;
      ptHit = grab;
    }

    // DFS to find the local cycle loop that contains the (possibly remapped)
    // grabbed point.
    final localCycleNodes = <int>{};
    final path = <int>[];
    final visitedDFS = <int>{};

    void findCycle(int u, int p) {
      visitedDFS.add(u);
      path.add(u);
      for (final v in adj[u]!) {
        if (v == p) continue;
        if (visitedDFS.contains(v)) {
          final idx = path.indexOf(v);
          if (idx != -1) {
            final cycle = path.sublist(idx);
            if (cycle.contains(ptHit)) {
              localCycleNodes.addAll(cycle);
            }
          }
        } else {
          findCycle(v, u);
        }
      }
      path.removeLast();
      visitedDFS.remove(u);
    }

    findCycle(ptHit, -1);

    final isCycle = localCycleNodes.isNotEmpty;

    int centre;
    List<int> rotPts;

    if (isCycle) {
      // Find the pivot node of the local cycle (node closest to subRoot)
      int cyclePivot = ptHit;
      var bestDepth = 99999;
      for (final node in localCycleNodes) {
        final d = depth[node];
        if (d != null && d < bestDepth) {
          bestDepth = d;
          cyclePivot = node;
        }
      }

      // If we clicked the pivot node, rotate the rest of the cycle around its neighbor.
      // Otherwise, rotate the whole local cycle around cyclePivot.
      centre = ptHit == cyclePivot
          ? (parent[ptHit] ?? (seg?.point1Index == ptHit ? seg!.point2Index : seg!.point1Index))
          : cyclePivot;

      // Rotate all cycle nodes and their descendants, except the center and subRoot.
      final rotSet = <int>{};
      final stk = <int>[...localCycleNodes];
      while (stk.isNotEmpty) {
        final cur = stk.removeLast();
        if (rotSet.contains(cur)) continue;
        rotSet.add(cur);
        for (final other in adj[cur]!) {
          if (parent[other] == cur) {
            stk.add(other);
          }
        }
      }
      rotSet.remove(centre);
      rotSet.remove(subRoot);
      rotPts = rotSet.toList();
    } else {
      centre = parent[ptHit] ?? (seg?.point1Index == ptHit ? seg!.point2Index : seg!.point1Index);
      final rot = <int>[];
      final stk = <int>[ptHit];
      while (stk.isNotEmpty) {
        final cur = stk.removeLast();
        if (rot.contains(cur)) continue;
        rot.add(cur);
        for (final other in adj[cur]!) {
          if (parent[other] == cur) {
            stk.add(other);
          }
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
