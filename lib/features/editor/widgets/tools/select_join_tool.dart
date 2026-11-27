part of '../figure_canvas.dart';

extension _SelectJoinTool on _FigureCanvasState {
  void handleSelectJoinStart(Offset w, EditorTool tool, Figure fig) {
    // ATTACH tool: can drag either an attached (orange) point OR any root pivot.
    if (tool == EditorTool.attach) {
      final ptHit = _hitTestPoint(w);
      if (ptHit < 0) {
        widget.controller.setSelectedPoint(null);
        widget.controller.setSelectedSegment(null);
        widget.controller.clearMultiSelect();
        widget.controller.forceUpdate();
        return;
      }
      if (ptHit >= 0) {
        final pt = fig.points[ptHit];
        final isAttachedPt = pt.isAttached;
        final isRoot = fig.rootIndices.contains(ptHit);

        if (isAttachedPt) {
          // Attached (orange) point: detach only the object that was explicitly
          // attached here. A child of the host figure can share the same joint;
          // using "root-less neighbour" heuristics would wrongly pull it away
          // together with the attached object.
          final detached = fig.detachAttachedAt(ptHit);
          if (detached != null) {
            final newPtIdx = detached.newRoot;
            final newRootX = fig.points[newPtIdx].x;
            final newRootY = fig.points[newPtIdx].y;
            // Detach appends a new root point. Key it at this frame so a
            // simple click (without dragging) still persists the detached
            // object's pose across scrubbing.
            widget.controller
                .recordPointsAtCurrentFrame([...detached.pointIndices, newPtIdx]);
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
      if (ptHit < 0) {
        widget.controller.setSelectedPoint(null);
        widget.controller.setSelectedSegment(null);
        widget.controller.clearMultiSelect();
        widget.controller.forceUpdate();
        return;
      }
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
      widget.controller.forceUpdate();
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
