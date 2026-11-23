part of '../figure_canvas.dart';

extension _SelectJoinTool on _FigureCanvasState {
  void handleSelectJoinStart(Offset w, EditorTool tool, Figure fig) {
    // ATTACH tool: can drag either an attached (orange) point OR any root pivot.
    if (tool == EditorTool.attach) {
      final ptHit = _hitTestPoint(w);
      if (ptHit >= 0) {
        final pt = fig.points[ptHit];
        final isAttachedPt = pt.isAttached;
        final isRoot = fig.rootIndices.contains(ptHit);

        if (isAttachedPt) {
          // Attached (orange) point: immediately detach on drag start.
          // Find which neighbor sub-tree is the "attached" figure (the one
          // that has no root of its own — its root was removed by joinPoints).
          final orangePt = fig.points[ptHit];
          final touchingSegs = fig.segments
              .where((s) =>
                  s.point1Index == ptHit || s.point2Index == ptHit)
              .toList();

          // For each neighbor, BFS excluding the orange point to get the sub-tree.
          // The attachment sub-tree has NO rootIndices in it. When the attached
          // figure connects to the joint through several segments (a "middle"
          // segment), every root-less sub-tree belongs to it, so we take the
          // UNION of them all.
          final attachComp = <int>{};
          int? firstAttachNeighbor;
          for (final s in touchingSegs) {
            final nb = s.point1Index == ptHit ? s.point2Index : s.point1Index;
            if (nb < 0 || nb >= fig.points.length) continue;
            // BFS from nb, not crossing ptHit.
            final comp = <int>{nb};
            final q = [nb];
            while (q.isNotEmpty) {
              final cur = q.removeAt(0);
              for (final seg in fig.segments) {
                if (seg.point1Index == ptHit || seg.point2Index == ptHit) continue;
                final o = seg.point1Index == cur
                    ? seg.point2Index
                    : seg.point2Index == cur
                        ? seg.point1Index
                        : -1;
                if (o >= 0 && !comp.contains(o)) {
                  comp.add(o);
                  q.add(o);
                }
              }
            }
            // If this sub-tree has no root, it's part of the attached figure.
            if (!fig.rootIndices.any(comp.contains)) {
              attachComp.addAll(comp);
              firstAttachNeighbor ??= nb;
            }
          }

          if (attachComp.isNotEmpty && firstAttachNeighbor != null) {
            // Split ALL segments from ptHit that go into the attachment sub-tree.
            // We must redirect them to a new root point at the orange position.
            final newRootX = orangePt.x;
            final newRootY = orangePt.y;
            final newPtIdx = fig.addPoint(newRootX, newRootY);
            for (final s in fig.segments) {
              if (s.point1Index == ptHit && attachComp.contains(s.point2Index)) {
                s.point1Index = newPtIdx;
              } else if (s.point2Index == ptHit &&
                  attachComp.contains(s.point1Index)) {
                s.point2Index = newPtIdx;
              }
            }
            if (!fig.rootIndices.contains(newPtIdx)) {
              fig.rootIndices.add(newPtIdx);
            }
            fig.repairRoots();
            orangePt.isAttached = false;
            // The detached sub-figure's overrides (colour, visibility, opacity,
            // collision) were keyed to the attached joint; move them to the new
            // root so they survive detaching.
            fig.moveFigureOverrides(ptHit, newPtIdx);
            widget.controller.pushHistory();
            widget.controller.forceUpdate();

            // Now drag newPtIdx + its full connected component.
            final newComp = fig.connectedComponent(newPtIdx).toList();
            final init = <int, Point2>{};
            for (final i in newComp) {
              init[i] = fig.points[i].clone();
            }
            widget.controller.setSelectedPoint(newPtIdx);
            widget.controller.setSelectedSegment(null);
            _drag
              ..reset()
              ..active = true
              ..isPoint = true
              ..ptIdx = newPtIdx
              ..startX = w.dx
              ..startY = w.dy
              ..startPtX = newRootX
              ..startPtY = newRootY
              ..connPts = newComp
              ..fkInit = init;
            widget.controller.forceUpdate();
            return;
          }

          // Fallback if couldn't identify attachment side: single-point drag.
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

        if (isRoot) {
          // Root (unattached): drag entire connected component to reposition.
          final allC = fig.connectedComponent(ptHit).toList()..add(ptHit);
          final init = <int, Point2>{};
          for (final i in allC) {
            init[i] = fig.points[i].clone();
          }
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
            ..startPtY = fig.points[ptHit].y
            ..connPts = allC
            ..fkInit = init;
          widget.controller.forceUpdate();
          return;
        }
      }
      // Nothing hit — pan fallback handled outside.
      return;
    }

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
        final sel = widget.controller.multiSelection;
        final already = sel.contains(ptHit);
        if (already) {
          _drag.maybeTap = true;
          _drag.tapWasSelected = true;
        } else {
          sel.add(ptHit);
          _drag.maybeTap = false;
        }
        widget.controller.setSelectedPoint(ptHit);
        final cs = _segmentTouching(fig, ptHit);
        widget.controller.setSelectedSegment(cs?.id);
        // Single isolated selection keeps the classic "Move All" behaviour
        // (drag the whole connected figure); a multi-selection moves only the
        // explicitly selected points.
        final moving = sel.length > 1 ? sel.toList() : <int>[
          ptHit,
          ..._findConnectedPoints(fig, ptHit),
        ];
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
        _captureAnchorForPoint(fig, ptHit, all: true);
        widget.controller.forceUpdate();
        return;
      }
      widget.controller.clearMultiSelect();
      widget.controller.setSelectedPoint(null);
      final segHit = _hitTestSegment(w);
      widget.controller.setSelectedSegment(segHit);
    }
  }

  void handleSelectJoinMove(Figure fig, _DragState d, Offset w) {
    final isJoin = widget.controller.activeTool == EditorTool.join;
    final isAttach = widget.controller.activeTool == EditorTool.attach;
    
    if ((isJoin || isAttach) &&
        d.isPoint &&
        d.ptIdx >= 0 &&
        d.ptIdx < fig.points.length &&
        !d.jointDone) {
      if (isAttach) {
        _handleAttachMove(fig, d, w);
      } else {
        _handleJoinMove(fig, d, w);
      }
    }
  }
}
