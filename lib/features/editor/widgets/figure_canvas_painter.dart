part of 'figure_canvas.dart';

// ===========================================================================
// Painter (extracted from figure_canvas.dart)
// ===========================================================================
// Painter
// ===========================================================================

class FigureCanvasPainter extends CustomPainter {
  final EditorController controller;
  final AppPalette palette;
  final ui.Image? Function(String? dataUri) imageFor;
  final int imageVersion;
  final int revision;

  FigureCanvasPainter({
    required this.controller,
    required this.palette,
    required this.imageFor,
    required this.imageVersion,
    required this.revision,
  });

  EditorController get c => controller;
  Figure get fig => c.figure;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paintInternal(canvas, size);
    } catch (e, st) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.red.shade900);
      final tp = TextPainter(
        text: TextSpan(
          text: 'PAINT ERROR:\n$e',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);
      tp.paint(canvas, const Offset(20, 20));
      debugPrint('PAINT ERROR: $e\n$st');
    }
  }

  void _paintInternal(Canvas canvas, Size size) {
    final cam = c.camera;
    final zoom = cam.zoom.isFinite && cam.zoom > 0 ? cam.zoom : 0.8;
    final cWidth = fig.canvasWidth.isFinite && fig.canvasWidth > 0 ? fig.canvasWidth : 800.0;
    final cHeight = fig.canvasHeight.isFinite && fig.canvasHeight > 0 ? fig.canvasHeight : 600.0;

    // Background (Workspace outside canvas).
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.backgroundElement);

    canvas.save();
    canvas.translate(size.width / 2 + cam.x, size.height / 2 + cam.y);
    canvas.scale(zoom);

    // Canvas bounds rect.
    final canvasRect = Rect.fromCenter(
      center: Offset.zero,
      width: cWidth,
      height: cHeight,
    );
    canvas.drawRect(
      canvasRect,
      Paint()..color = parseHexColor(fig.canvasColor) ?? palette.background,
    );
    canvas.drawRect(
      canvasRect,
      Paint()
        ..color = const Color(0xFF9CA3AF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    if (c.showAxis) {
      final axisPaint = Paint()
        ..color =
            const Color(0x66EF4444) // Semi-transparent red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / zoom;
      // Y-axis (x=0)
      canvas.drawLine(const Offset(0, -9999), const Offset(0, 9999), axisPaint);
      // X-axis (y=0)
      canvas.drawLine(const Offset(-9999, 0), const Offset(9999, 0), axisPaint);
    }

    if (c.snapEnabled) {
      final g = c.snapGrid > 0 ? c.snapGrid : 20;
      final gridPaint = Paint()
        ..color =
            const Color(0x223B82F6) // faint blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / zoom;
      final halfW = cWidth / 2;
      final halfH = cHeight / 2;
      for (var x = -halfW; x <= halfW; x += g) {
        canvas.drawLine(Offset(x, -halfH), Offset(x, halfH), gridPaint);
      }
      for (var y = -halfH; y <= halfH; y += g) {
        canvas.drawLine(Offset(-halfW, y), Offset(halfW, y), gridPaint);
      }
    }

    if (c.isAnimateMode) {
      _paintOnion(canvas, size);
    }
    // Same compositing rule as onion skin: opaque geometry first, then fade
    // the whole bucket once so overlapping parts never stack their alpha.
    final opacityGroups = OpacityPaintGroups();
    _paintCycleFills(canvas, opacityGroups);
    _paintSegments(canvas, opacityGroups);
    opacityGroups.paint(canvas);
    _paintCollision(canvas);
    if (c.showConnectors) _paintConnectors(canvas);
    if (c.activeTool == EditorTool.curve) _paintCurveControls(canvas);
    if (c.isAssetMode) _paintAssetEditor(canvas);
    if (!c.isPlaying) _paintPoints(canvas);

    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Connector lines between sub-figures
  // -------------------------------------------------------------------------

  void _paintConnectors(Canvas canvas) {
    if (c.isAnimateMode) return;
    if (c.isPlaying) return;
    final paint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2 / c.camera.zoom;
    // Blue connector line along every existing segment (e.g. A->B). Curved
    // segments draw their quadratic curve so the connector matches the shape.
    for (final seg in fig.segments) {
      final style = fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
      if (style.hidden) continue;
      if (seg.point1Index < 0 ||
          seg.point1Index >= fig.points.length ||
          seg.point2Index < 0 ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final pa = fig.points[seg.point1Index], pb = fig.points[seg.point2Index];
      final path = Path()..moveTo(pa.x, pa.y);
      if (style.curved) {
        final mx = (pa.x + pb.x) / 2;
        final my = (pa.y + pb.y) / 2;
        final cpx = style.controlDX != null
            ? mx + style.controlDX!
            : mx + (-(pb.y - pa.y) * style.curvature);
        final cpy = style.controlDY != null
            ? my + style.controlDY!
            : my + ((pb.x - pa.x) * style.curvature);
        path.quadraticBezierTo(cpx, cpy, pb.x, pb.y);
      } else {
        path.lineTo(pb.x, pb.y);
      }
      canvas.drawPath(path, paint);
    }
  }

  // -------------------------------------------------------------------------
  // Asset editor (image segment bounding box + resize/rotate handles)
  // -------------------------------------------------------------------------

  void _paintAssetEditor(Canvas canvas) {
    if (c.isPlaying) return;
    final seg = _selectedImageSegment();
    if (seg == null) return;
    if (seg.point1Index >= fig.points.length ||
        seg.point2Index >= fig.points.length) {
      return;
    }
    final p1 = fig.points[seg.point1Index];
    final p2 = fig.points[seg.point2Index];
    if (seg.imageData == null) return;
    final image = imageFor(seg.imageData);
    if (image == null) return;
    final style = fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
    final size = _resolveImageSize(style, image);
    final mx = (p1.x + p2.x) / 2 + style.imageOffsetX;
    final my = (p1.y + p2.y) / 2 + style.imageOffsetY;
    final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final rotate = segAngle + style.imageRotate * math.pi / 180;

    final z = c.camera.zoom;
    final hw = size.width / 2, hh = size.height / 2;

    final pts = _assetHandles(hw, hh, rotate, mx, my);
    // Box outline using the four corner handles (0,2,4,6).
    const cornerIdx = [0, 2, 4, 6];
    final box = Path()..moveTo(pts[cornerIdx[0]].dx, pts[cornerIdx[0]].dy);
    for (final i in cornerIdx.skip(1)) {
      box.lineTo(pts[i].dx, pts[i].dy);
    }
    box.close();
    canvas.drawPath(
      box,
      Paint()
        ..color = const Color(0xFF8B5CF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / z,
    );
    // Rotation handle (last index) + connecting line to top-center.
    final rotP = pts[8];
    final top = pts[1];
    canvas.drawLine(
      Offset(top.dx, top.dy),
      Offset(rotP.dx, rotP.dy),
      Paint()
        ..color = const Color(0xFF8B5CF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / z,
    );
    // 8 resize handles + 1 rotation handle.
    for (var i = 0; i < pts.length; i++) {
      final isRot = i == 8;
      final r = (isRot ? 6 : 5) / z;
      canvas.drawCircle(
        Offset(pts[i].dx, pts[i].dy),
        r,
        Paint()
          ..color = isRot ? const Color(0xFFF59E0B) : const Color(0xFF8B5CF6),
      );
      canvas.drawCircle(
        Offset(pts[i].dx, pts[i].dy),
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / z,
      );
    }
  }

  Segment? _selectedImageSegment() {
    final id = c.assetSegmentId ?? c.selectedSegmentId;
    if (id == null) return null;
    final seg = fig.getSegment(id);
    if (seg == null || !seg.isImage) return null;
    return seg;
  }

  // -------------------------------------------------------------------------
  // Onion skins
  // -------------------------------------------------------------------------

  void _paintOnion(Canvas canvas, Size size) {
    if (c.isPlaying) return;
    final anim = c.currentAnimation;
    if (anim == null) return;

    bool isProtectionPin(double time) {
      final frac = time - time.floorToDouble();
      // Skip post-edit cut pins (t+0.001). Keep pre-edit cut pins (t-0.001)
      // because they represent preserved state useful for onion.
      return frac > 0.0001 && frac < 0.02;
    }

    PointKeyframe? poseAt(PointTrack track, double t, int dir) {
      final keys = track.keyframes;
      if (keys.isEmpty) return null;
      if (dir < 0) {
        for (var i = keys.length - 1; i >= 0; i--) {
          final kf = keys[i];
          if (kf.time < t - 0.001 && !isProtectionPin(kf.time)) return kf;
        }
      } else {
        for (var i = 0; i < keys.length; i++) {
          final kf = keys[i];
          if (kf.time > t + 0.001 && !isProtectionPin(kf.time)) return kf;
        }
      }
      return null;
    }

    Color opaque(Color? color) =>
        (color ?? const Color(0xFFD1D5DB)).withValues(alpha: 1);

    void ghost(double t, int dir, double alpha) {
      final ghostTimes = <double>[];
      final pts = List<Point2>.generate(fig.points.length, (i) {
        final track = anim.getTrack(i);
        if (track == null) return fig.points[i];
        final kf = poseAt(track, t, dir);
        if (kf == null) return fig.points[i];
        ghostTimes.add(kf.time);
        return Point2(kf.x, kf.y);
      });
      // No pose before/after this frame: nothing to ghost, so don't draw
      // a duplicate of the live figure at the current position (which made
      // the first and last frames show stray onion skins).
      if (ghostTimes.isEmpty) return;
      // Resolve styles at the frame the ghost actually represents, so a
      // property keyed at the current frame does NOT leak into the ghost
      // (otherwise both the live object and its faint copy look changed).
      final ghostTime = ghostTimes.reduce((a, b) => a + b) / ghostTimes.length;

      // Draw the entire ghost with the segment's ORIGINAL (opaque) colours
      // into ONE layer, then composite the layer once with [alpha]. Applying
      // alpha per segment makes overlaps accumulate (0.3 -> 0.51 -> 0.66 ...)
      // and look thicker; this keeps every part of the ghost evenly faint.
      canvas.saveLayer(
        const Rect.fromLTRB(-100000, -100000, 100000, 100000),
        Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
      );

      for (final seg in fig.segments) {
        final style = fig.styleFor(seg, ghostTime, enabled: c.isAnimateMode);
        if (style.hidden) continue;
        if (seg.isNone) continue;
        if (c.isAnimateMode && !_visibleAtSeg(fig, seg, ghostTime)) {
          continue;
        }
        if (seg.point1Index >= pts.length || seg.point2Index >= pts.length) {
          continue;
        }
        final p1 = pts[seg.point1Index];
        final p2 = pts[seg.point2Index];
        if (seg.type == 'image') {
          _paintImageSegment(
            canvas,
            seg,
            p1,
            p2,
            1.0,
            style: style,
            time: ghostTime,
          );
          continue;
        }
        final overColor = _colorOverrideAtSeg(fig, seg, ghostTime);
        final strokeColor = opaque(parseHexColor(overColor ?? style.color));
        final ghostPaint = Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = style.width <= 0 ? 3 : style.width;
        if (seg.type == 'circle') {
          final mx = (p1.x + p2.x) / 2;
          final my = (p1.y + p2.y) / 2;
          final r = math.max(
            math.sqrt(
                  (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y),
                ) /
                2,
            1.0,
          );
          if (style.filled) {
            canvas.drawCircle(
              Offset(mx, my),
              r,
              Paint()
                ..color = opaque(
                  parseHexColor(overColor) ??
                      parseHexColor(style.fillColor) ??
                      parseHexColor(style.color),
                ),
            );
          }
          canvas.drawCircle(Offset(mx, my), r, ghostPaint);
        } else {
          _drawSegmentLine(canvas, ghostPaint, seg, p1, p2, style);
        }
      }
      canvas.restore();
    }

    if (c.onionPrev) ghost(c.currentTime, -1, 0.3);
    if (c.onionNext) ghost(c.currentTime, 1, 0.5);
  }

  // -------------------------------------------------------------------------
  // Cycle fills
  // -------------------------------------------------------------------------

  void _paintCycleFills(Canvas canvas, OpacityPaintGroups groups) {
    if (fig.segments.isEmpty) return;
    final adj = <int, List<int>>{};
    for (var i = 0; i < fig.points.length; i++) {
      adj[i] = [];
    }
    for (final s in fig.segments) {
      if (fig.styleFor(s, c.currentTime, enabled: c.isAnimateMode).hidden ||
          s.isNone) {
        continue;
      }
      if (s.point1Index >= 0 &&
          s.point1Index < fig.points.length &&
          s.point2Index >= 0 &&
          s.point2Index < fig.points.length) {
        adj[s.point1Index]!.add(s.point2Index);
        adj[s.point2Index]!.add(s.point1Index);
      }
    }

    final visitedPts = <int>{};
    final cf = fig.cycleFills;

    for (var start = 0; start < fig.points.length; start++) {
      if (visitedPts.contains(start)) continue;
      final compPts = <int>{};
      final q = <int>[start];
      while (q.isNotEmpty) {
        final idx = q.removeAt(0);
        if (visitedPts.contains(idx)) continue;
        visitedPts.add(idx);
        compPts.add(idx);
        for (final nb in adj[idx]!) {
          if (!visitedPts.contains(nb)) q.add(nb);
        }
      }
      if (compPts.length < 3) continue;
      if (c.isAnimateMode && !_visibleAt(fig, compPts.first, c.currentTime)) {
        continue;
      }

      final deg = <int, int>{};
      final nonCyclePoints = <int>[];
      for (final pi in compPts) {
        deg[pi] = adj[pi]!.length;
        if (adj[pi]!.length != 2) nonCyclePoints.add(pi);
      }

      if (nonCyclePoints.isEmpty) {
        final arr = compPts.toList();
        var cur = arr[0];
        var prev = -1;
        final ordered = <int>[cur];
        for (var i = 0; i < compPts.length; i++) {
          int? nb;
          for (final n in adj[cur]!) {
            if (compPts.contains(n) && n != prev) {
              nb = n;
              break;
            }
          }
          if (nb == null) break;
          prev = cur;
          cur = nb;
          ordered.add(cur);
        }
        if (ordered.length >= 3 && ordered.first == ordered.last) {
          final pts = ordered.sublist(0, ordered.length - 1);
          final sorted = [...pts]..sort();
          final key = sorted.join(',');
          if (!cf.containsKey(key)) {
            Segment? filledSeg;
            for (final s in fig.segments) {
              if (compPts.contains(s.point1Index) ||
                  compPts.contains(s.point2Index)) {
                filledSeg = s;
                break;
              }
            }
            cf[key] = CycleFill(
              filled: filledSeg?.filled != false,
              fillColor: filledSeg?.fillColor,
            );
          }
          final entry = cf[key]!;
          final filled = fig.frameBool(
            'cycle:$key:filled',
            c.currentTime,
            entry.filled,
          );
          if (filled) {
            final overColor = _colorOverrideAt(
              fig,
              ordered.first,
              c.currentTime,
            );
            final fillColor =
                parseHexColor(overColor) ??
                parseHexColor(
                  fig.frameNullableString(
                    'cycle:$key:fillColor',
                    c.currentTime,
                    entry.fillColor,
                  ),
                ) ??
                const Color(0xFFD1D5DB);
            final path = _cyclePath(pts, c.currentTime);
            groups.add(_opacityAtPoint(fig, ordered.first, c.currentTime), () {
              canvas.drawPath(path, Paint()..color = fillColor);
            });
          }
        }
        continue;
      }

      final leafQ = nonCyclePoints.where((pi) => deg[pi] == 1).toList();
      while (leafQ.isNotEmpty) {
        final leaf = leafQ.removeAt(0);
        compPts.remove(leaf);
        for (final nb in adj[leaf]!) {
          if (compPts.contains(nb)) {
            deg[nb] = deg[nb]! - 1;
            if (deg[nb] == 1) leafQ.add(nb);
          }
        }
      }
      if (compPts.length < 3) continue;

      final remaining = compPts.toList();
      final foundKeys = <String>{};
      for (final seed in remaining) {
        final stack = <({int pt, int prev, List<int> path})>[
          (pt: seed, prev: -1, path: [seed]),
        ];
        while (stack.isNotEmpty) {
          final cur = stack.removeLast();
          for (final nb in adj[cur.pt]!) {
            if (!compPts.contains(nb) || nb == cur.prev) continue;
            if (nb == seed && cur.path.length >= 3) {
              final keySet = {...cur.path, seed}.toList()..sort();
              final key = keySet.join(',');
              if (!foundKeys.contains(key)) {
                foundKeys.add(key);
                if (!cf.containsKey(key)) {
                  cf[key] = CycleFill(filled: true, fillColor: null);
                }
                final entry = cf[key]!;
                final filled = fig.frameBool(
                  'cycle:$key:filled',
                  c.currentTime,
                  entry.filled,
                );
                if (filled) {
                  final overColor = _colorOverrideAt(fig, seed, c.currentTime);
                  final fillColor =
                      parseHexColor(overColor) ??
                      parseHexColor(
                        fig.frameNullableString(
                          'cycle:$key:fillColor',
                          c.currentTime,
                          entry.fillColor,
                        ),
                      ) ??
                      const Color(0xFFD1D5DB);
                  final pts = [...cur.path, seed];
                  final path = _cyclePath(pts, c.currentTime);
                  groups.add(_opacityAtPoint(fig, seed, c.currentTime), () {
                    canvas.drawPath(path, Paint()..color = fillColor);
                  });
                }
              }
              continue;
            }
            if (!cur.path.contains(nb)) {
              stack.add((pt: nb, prev: cur.pt, path: [...cur.path, nb]));
            }
          }
        }
      }
    }
  }

  Path _cyclePath(List<int> pts, double time) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(fig.points[pts[0]].x, fig.points[pts[0]].y);
    for (var j = 0; j < pts.length; j++) {
      final next = (j + 1) % pts.length;
      final seg = _segmentBetween(pts[j], pts[next]);
      final style = seg == null
          ? null
          : fig.styleFor(seg, time, enabled: c.isAnimateMode);
      if (style != null &&
          style.curved &&
          style.controlDX != null &&
          style.controlDY != null) {
        final mx = (fig.points[pts[j]].x + fig.points[pts[next]].x) / 2;
        final my = (fig.points[pts[j]].y + fig.points[pts[next]].y) / 2;
        path.quadraticBezierTo(
          mx + style.controlDX!,
          my + style.controlDY!,
          fig.points[pts[next]].x,
          fig.points[pts[next]].y,
        );
      } else {
        path.lineTo(fig.points[pts[next]].x, fig.points[pts[next]].y);
      }
    }
    path.close();
    return path;
  }

  Segment? _segmentBetween(int a, int b) {
    for (final s in fig.segments) {
      if ((s.point1Index == a && s.point2Index == b) ||
          (s.point1Index == b && s.point2Index == a)) {
        return s;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Segments
  // -------------------------------------------------------------------------

  void _paintSegments(Canvas canvas, OpacityPaintGroups groups) {
    final sorted = fig.segmentsInDrawOrder(
      c.isAnimateMode ? c.currentTime : null,
    );
    for (final seg in sorted) {
      final style = fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
      if (style.hidden || seg.isNone) continue;
      if (c.isAnimateMode && !_visibleAtSeg(fig, seg, c.currentTime)) {
        continue;
      }
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];

      final opacity = _opacityAtSeg(fig, seg, c.currentTime);
      final overColor = _colorOverrideAtSeg(fig, seg, c.currentTime);

      groups.add(opacity, () {
        // Draw opaque into the bucket; the layer's fade happens once in
        // OpacityPaintGroups.paint(), exactly like the onion-skin ghosts.
        if (seg.type == 'line') {
          final baseColor =
              parseHexColor(overColor ?? style.color) ??
              const Color(0xFFD1D5DB);
          final paint = Paint()
            ..color = baseColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width <= 0 ? 3 : style.width
            ..strokeCap = _capFor(style.lineCap);
          _drawSegmentLine(canvas, paint, seg, p1, p2, style);
        } else if (seg.type == 'circle') {
          double mx = (p1.x + p2.x) / 2;
          double my = (p1.y + p2.y) / 2;
          if (style.curved) {
            final cpx = style.controlDX != null
                ? mx + style.controlDX!
                : mx + (-(p2.y - p1.y) * style.curvature);
            final cpy = style.controlDY != null
                ? my + style.controlDY!
                : my + ((p2.x - p1.x) * style.curvature);
            mx = (p1.x + p2.x) / 4 + cpx / 2;
            my = (p1.y + p2.y) / 4 + cpy / 2;
          }
          final r = math.max(
            math.sqrt(
                  (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y),
                ) /
                2,
            1.0,
          );
          if (style.filled) {
            final baseColor =
                parseHexColor(overColor) ??
                parseHexColor(style.fillColor) ??
                parseHexColor(style.color) ??
                const Color(0xFFD1D5DB);
            canvas.drawCircle(Offset(mx, my), r, Paint()..color = baseColor);
          }
          final strokeColor =
              parseHexColor(overColor ?? style.color) ??
              const Color(0xFFD1D5DB);
          canvas.drawCircle(
            Offset(mx, my),
            r,
            Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.width <= 0 ? 3 : style.width,
          );
        } else if (seg.type == 'image') {
          _paintImageSegment(canvas, seg, p1, p2, 1.0, style: style);
        } else if (seg.type == 'text') {
          _paintTextSegment(canvas, seg, style, p1, p2, 1.0, overColor);
        }
      });
    }
  }

  /// Draws a `text` segment: the label centred at the segment midpoint and
  /// rotated to the segment angle so its two points can animate position,
  /// rotation, and (via the inspector) scale.
  void _paintTextSegment(
    Canvas canvas,
    Segment seg,
    SegmentFrameStyle style,
    Point2 p1,
    Point2 p2,
    double opacity,
    String? overColor,
  ) {
    final text = style.text;
    if (text == null || text.isEmpty) return;
    final mx = (p1.x + p2.x) / 2;
    final my = (p1.y + p2.y) / 2;
    final angle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final baseColor =
        parseHexColor(overColor ?? style.color) ?? const Color(0xFFD1D5DB);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: baseColor.withValues(alpha: baseColor.a * opacity),
          fontSize: style.textSize <= 0 ? 32 : style.textSize,
          fontWeight: FontWeight.w600,
          fontFamily: 'Onest',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(mx, my);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// Game-dev markers: a dashed green bounding box around any figure flagged
  /// as collision, plus a green badge on individual collision segments.
  void _paintCollision(Canvas canvas) {
    if (fig.segments.isEmpty) return;
    final z = c.camera.zoom;
    final green = const Color(0xFF22C55E);
    final badgePaint = Paint()
      ..color = green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / z;
    final fillPaint = Paint()
      ..color = const Color(0x3322C55E)
      ..style = PaintingStyle.fill;

    final drawnFigs = <int>{};
    for (final seg in fig.segmentsInDrawOrder(
      c.isAnimateMode ? c.currentTime : null,
    )) {
      final style = fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
      if (style.hidden || seg.isNone) continue;
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final key = fig.segmentFigureKey(seg);
      if (key < 0) continue;

      if (!drawnFigs.contains(key)) {
        drawnFigs.add(key);
        final visible =
            !c.isAnimateMode || _visibleAt(fig, seg.point1Index, c.currentTime);
        if (visible && fig.getFigureCollision(key)) {
          final comp = fig.connectedComponent(key);
          double minX = double.infinity,
              minY = double.infinity,
              maxX = -double.infinity,
              maxY = -double.infinity;
          for (final i in comp) {
            final p = fig.points[i];
            if (p.x < minX) minX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.x > maxX) maxX = p.x;
            if (p.y > maxY) maxY = p.y;
          }
          if (minX != double.infinity) {
            final rect = Rect.fromLTRB(minX - 8, minY - 8, maxX + 8, maxY + 8);
            final path = Path()
              ..addRRect(
                RRect.fromRectAndRadius(rect, const Radius.circular(6)),
              );
            canvas.drawPath(path, fillPaint);
            canvas.drawPath(path, badgePaint);
            final tp = TextPainter(
              text: const TextSpan(
                text: 'C',
                style: TextStyle(
                  color: Color(0xFF22C55E),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, Offset(rect.left + 2, rect.top - tp.height - 2));
          }
        }
      }

      if (style.isCollision) {
        final p1 = fig.points[seg.point1Index];
        final p2 = fig.points[seg.point2Index];
        final mx = (p1.x + p2.x) / 2 + style.imageOffsetX;
        final my = (p1.y + p2.y) / 2 + style.imageOffsetY;
        canvas.drawCircle(Offset(mx, my), 6 / z, Paint()..color = green);
        canvas.drawCircle(
          Offset(mx, my),
          6 / z,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z,
        );
      }
    }
  }

  void _drawSegmentLine(
    Canvas canvas,
    Paint paint,
    Segment seg,
    Point2 p1,
    Point2 p2, [
    SegmentFrameStyle? style,
  ]) {
    style ??= fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
    final path = Path()..moveTo(p1.x, p1.y);
    if (style.curved) {
      final mx = (p1.x + p2.x) / 2;
      final my = (p1.y + p2.y) / 2;
      final cpx = style.controlDX != null
          ? mx + style.controlDX!
          : mx + (-(p2.y - p1.y) * style.curvature);
      final cpy = style.controlDY != null
          ? my + style.controlDY!
          : my + ((p2.x - p1.x) * style.curvature);
      path.quadraticBezierTo(cpx, cpy, p2.x, p2.y);
    } else {
      path.lineTo(p2.x, p2.y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintImageSegment(
    Canvas canvas,
    Segment seg,
    Point2 p1,
    Point2 p2,
    double opacity, {
    SegmentFrameStyle? style,
    double? time,
  }) {
    final t = time ?? c.currentTime;
    style ??= fig.styleFor(seg, t, enabled: c.isAnimateMode);
    int imageIndex = seg.activeImageIndex;
    if (c.isAnimateMode) {
      imageIndex = fig.getSegmentImageIndex(seg.id, t) ?? imageIndex;
    }
    String? imageData =
        seg.imageDataList.isNotEmpty &&
            imageIndex >= 0 &&
            imageIndex < seg.imageDataList.length
        ? seg.imageDataList[imageIndex]
        : null;

    final image = imageFor(imageData);
    if (image == null) return;
    double mx = (p1.x + p2.x) / 2;
    double my = (p1.y + p2.y) / 2;
    if (style.curved) {
      final cpx = style.controlDX != null
          ? mx + style.controlDX!
          : mx + (-(p2.y - p1.y) * style.curvature);
      final cpy = style.controlDY != null
          ? my + style.controlDY!
          : my + ((p2.x - p1.x) * style.curvature);
      mx = (p1.x + p2.x) / 4 + cpx / 2;
      my = (p1.y + p2.y) / 4 + cpy / 2;
    }
    final ox = style.imageOffsetX;
    final oy = style.imageOffsetY;
    final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final rotate = segAngle + style.imageRotate * math.pi / 180;
    final cx = mx + ox;
    final cy = my + oy;
    final size = _resolveImageSize(style, image);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotate);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.restore();
  }

  Size _resolveImageSize(SegmentFrameStyle style, ui.Image image) {
    var w = style.imageWidth is num
        ? (style.imageWidth as num).toDouble()
        : 100.0;
    var h = style.imageHeight is num
        ? (style.imageHeight as num).toDouble()
        : 100.0;
    final wAuto = style.imageWidth == 'auto';
    final hAuto = style.imageHeight == 'auto';
    final ar = image.width / image.height;
    if (wAuto && hAuto) {
      w = 100;
      h = 100 / ar;
    } else if (wAuto) {
      w = h * ar;
    } else if (hAuto) {
      h = w / ar;
    }
    return Size(w, h);
  }

  StrokeCap _capFor(String cap) {
    switch (cap) {
      case 'square':
        return StrokeCap.square;
      case 'butt':
        return StrokeCap.butt;
      default:
        return StrokeCap.round;
    }
  }

  // -------------------------------------------------------------------------
  // Curve controls
  // -------------------------------------------------------------------------

  void _paintCurveControls(Canvas canvas) {
    if (c.isPlaying) return;
    final z = c.camera.zoom;
    for (final seg in fig.segments) {
      final style = fig.styleFor(seg, c.currentTime, enabled: c.isAnimateMode);
      if (!style.curved || style.controlDX == null || style.controlDY == null) {
        continue;
      }
      if (style.hidden) continue;
      if (c.isAnimateMode && !_visibleAtSeg(fig, seg, c.currentTime)) {
        continue;
      }
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];
      final mx = (p1.x + p2.x) / 2;
      final my = (p1.y + p2.y) / 2;
      final cx = mx + style.controlDX!;
      final cy = my + style.controlDY!;

      final dash = Path()
        ..moveTo(p1.x, p1.y)
        ..lineTo(cx, cy)
        ..lineTo(p2.x, p2.y);
      canvas.drawPath(
        dash,
        Paint()
          ..color = const Color(0x66EC4899)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
      // Same on-screen size as the segment points drawn by _paintPoints.
      final r = 5 / z;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = const Color(0xFFEC4899),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / z,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Points
  // -------------------------------------------------------------------------

  void _paintPoints(Canvas canvas) {
    final z = c.camera.zoom;
    for (var i = 0; i < fig.points.length; i++) {
      if (c.isAnimateMode && !_visibleAt(fig, i, c.currentTime)) continue;
      final pt = fig.points[i];
      final multi = c.multiSelection.contains(i);
      final sel = i == c.selectedPointIndex;
      final r =
          (sel
              ? 7
              : multi
              ? 6.5
              : 5) /
          z;
      final isRoot = fig.rootIndices.contains(i);
      final Color fill;
      if (sel) {
        fill = const Color(0xFFFACC15);
      } else if (multi) {
        fill = const Color(0xFF22D3EE); // cyan for multi-selected points
      } else if (pt.isAttached) {
        fill = const Color(0xFFF97316); // orange for attached pivot
      } else if (isRoot) {
        fill = const Color(0xFFEF4444);
      } else if (c.pointModes[i] == 'static') {
        fill = const Color(0xFF6B7280);
      } else {
        fill = const Color(0xFF0EA5E9);
      }
      canvas.drawCircle(Offset(pt.x, pt.y), r, Paint()..color = fill);
      canvas.drawCircle(
        Offset(pt.x, pt.y),
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / z,
      );
    }
  }

  bool _visibleAt(Figure f, int pointIdx, double t) {
    if (pointIdx < 0 || pointIdx >= f.points.length) return true;
    return f.getFigureVisibility(f.figureKeyFor(pointIdx), t);
  }

  bool _visibleAtSeg(Figure f, Segment seg, double t) {
    final k = f.segmentFigureKey(seg);
    if (k < 0) return true;
    return f.getFigureVisibility(k, t);
  }

  double _opacityAtSeg(Figure f, Segment seg, double t) {
    final k = f.segmentFigureKey(seg);
    if (k < 0) return 1.0;
    return f.getFigureOpacity(k, t);
  }

  double _opacityAtPoint(Figure f, int point, double t) {
    if (!c.isAnimateMode) return 1.0;
    final k = f.figureKeyFor(point);
    if (k < 0) return 1.0;
    return f.getFigureOpacity(k, t);
  }

  String? _colorOverrideAt(Figure f, int pointIdx, double t) {
    if (!c.isAnimateMode) return null;
    if (pointIdx < 0 || pointIdx >= f.points.length) return null;
    return f.getFigureColorOverride(f.figureKeyFor(pointIdx), t);
  }

  String? _colorOverrideAtSeg(Figure f, Segment seg, double t) {
    if (!c.isAnimateMode) return null;
    final k = f.segmentFigureKey(seg);
    if (k < 0) return null;
    return f.getFigureColorOverride(k, t);
  }

  @override
  bool shouldRepaint(covariant FigureCanvasPainter oldDelegate) {
    return oldDelegate.imageVersion != imageVersion ||
        oldDelegate.controller != controller ||
        oldDelegate.palette != palette ||
        oldDelegate.revision != revision;
  }
}

// -------------------------------------------------------------------------
// Asset editor geometry (shared by state and painter)
// -------------------------------------------------------------------------

/// Returns the 9 asset handles for an un-transformed half-extent box:
/// [0]=top-right, [1]=top-center, [2]=top-left, [3]=left-center,
/// [4]=bottom-left, [5]=bottom-center, [6]=bottom-right, [7]=right-center,
/// and [8]=rotation handle (outside above top-center).
List<Offset> _assetHandles(
  double hw,
  double hh,
  double rotate,
  double cx,
  double cy,
) {
  final cosR = math.cos(rotate), sinR = math.sin(rotate);
  Offset tr(Offset local) => Offset(
    cx + local.dx * cosR - local.dy * sinR,
    cy + local.dx * sinR + local.dy * cosR,
  );
  const corners = [
    Offset(1, -1),
    Offset(0, -1),
    Offset(-1, -1),
    Offset(-1, 0),
    Offset(-1, 1),
    Offset(0, 1),
    Offset(1, 1),
    Offset(1, 0),
  ];
  final pts = corners.map((o) => tr(Offset(o.dx * hw, o.dy * hh))).toList();
  final rotLocal = Offset(0, -(hh + 28));
  pts.add(tr(rotLocal));
  return pts;
}
