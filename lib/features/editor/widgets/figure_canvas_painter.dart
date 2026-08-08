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

  FigureCanvasPainter({
    required this.controller,
    required this.palette,
    required this.imageFor,
    required this.imageVersion,
  });

  EditorController get c => controller;
  Figure get fig => c.figure;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = c.camera;

    // Background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.background,
    );

    canvas.save();
    canvas.translate(size.width / 2 + cam.x, size.height / 2 + cam.y);
    canvas.scale(cam.zoom);

    // Canvas bounds rect.
    final canvasRect = Rect.fromCenter(
      center: Offset.zero,
      width: fig.canvasWidth,
      height: fig.canvasHeight,
    );
    canvas.drawRect(
      canvasRect,
      Paint()
        ..color = parseHexColor(fig.canvasColor) ?? palette.backgroundElement,
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
        ..color = const Color(0x66EF4444) // Semi-transparent red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / cam.zoom;
      // Y-axis (x=0)
      canvas.drawLine(const Offset(0, -9999), const Offset(0, 9999), axisPaint);
      // X-axis (y=0)
      canvas.drawLine(const Offset(-9999, 0), const Offset(9999, 0), axisPaint);
    }

    if (c.isAnimateMode) {
      _paintOnion(canvas, size);
    }
    _paintCycleFills(canvas);
    _paintSegments(canvas);
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
      if (seg.hidden) continue;
      if (seg.point1Index < 0 ||
          seg.point1Index >= fig.points.length ||
          seg.point2Index < 0 ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final pa = fig.points[seg.point1Index], pb = fig.points[seg.point2Index];
      final path = Path()..moveTo(pa.x, pa.y);
      if (seg.curved) {
        final mx = (pa.x + pb.x) / 2;
        final my = (pa.y + pb.y) / 2;
        final cpx = seg.controlDX != null
            ? mx + seg.controlDX!
            : mx + (-(pb.y - pa.y) * seg.curvature);
        final cpy = seg.controlDY != null
            ? my + seg.controlDY!
            : my + ((pb.x - pa.x) * seg.curvature);
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
    if (seg.point1Index >= fig.points.length || seg.point2Index >= fig.points.length) {
      return;
    }
    final p1 = fig.points[seg.point1Index];
    final p2 = fig.points[seg.point2Index];
    if (seg.imageData == null) return;
    final image = imageFor(seg.imageData);
    if (image == null) return;
    final size = _resolveImageSize(seg, image);
    final mx = (p1.x + p2.x) / 2 + seg.imageOffsetX;
    final my = (p1.y + p2.y) / 2 + seg.imageOffsetY;
    final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final rotate = segAngle + seg.imageRotate * math.pi / 180;

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
        Paint()..color = isRot ? const Color(0xFFF59E0B) : const Color(0xFF8B5CF6),
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

    PointKeyframe? poseAt(PointTrack track, double t, int dir) {
      final keys = track.keyframes;
      if (keys.isEmpty) return null;
      if (dir < 0) {
        for (var i = keys.length - 1; i >= 0; i--) {
          if (keys[i].time < t - 0.001) return keys[i];
        }
      } else {
        for (var i = 0; i < keys.length; i++) {
          if (keys[i].time > t + 0.001) return keys[i];
        }
      }
      return null;
    }

    void ghost(double t, int dir, double alpha) {
      final pts = List<Point2>.generate(fig.points.length, (i) {
        final track = anim.getTrack(i);
        if (track == null) return fig.points[i];
        final kf = poseAt(track, t, dir);
        if (kf == null) return fig.points[i];
        return Point2(kf.x, kf.y);
      });
      for (final seg in fig.segments) {
        if (seg.hidden) continue;
        if (seg.type == 'image' || seg.isNone) continue;
        if (c.isAnimateMode &&
            !_visibleAt(fig, seg.point1Index, t)) {
          continue;
        }
        if (seg.point1Index >= pts.length || seg.point2Index >= pts.length) {
          continue;
        }
        final p1 = pts[seg.point1Index];
        final p2 = pts[seg.point2Index];
        final overColor = _colorOverrideAt(fig, seg.point1Index, t);
        final strokeColor =
            (parseHexColor(overColor ?? seg.color) ?? const Color(0xFFD1D5DB))
                .withValues(alpha: alpha);
        if (seg.type == 'circle') {
          final mx = (p1.x + p2.x) / 2;
          final my = (p1.y + p2.y) / 2;
          final r = math.max(
            math.sqrt((p2.x - p1.x) * (p2.x - p1.x) +
                    (p2.y - p1.y) * (p2.y - p1.y)) /
                2,
            1.0,
          );
          if (seg.filled) {
            final fillColor =
                (parseHexColor(overColor) ??
                        parseHexColor(seg.fillColor) ??
                        parseHexColor(seg.color) ??
                        const Color(0xFFD1D5DB))
                    .withValues(alpha: alpha);
            canvas.drawCircle(Offset(mx, my), r, Paint()..color = fillColor);
          }
          canvas.drawCircle(
            Offset(mx, my),
            r,
            Paint()
              ..color = strokeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = seg.width <= 0 ? 3 : seg.width,
          );
        } else {
          final paint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = seg.width <= 0 ? 3 : seg.width;
          _drawSegmentLine(canvas, paint, seg, p1, p2);
        }
      }
    }

    if (c.onionPrev) ghost(c.currentTime, -1, 0.3);
    if (c.onionNext) ghost(c.currentTime, 1, 0.5);
  }

  // -------------------------------------------------------------------------
  // Cycle fills
  // -------------------------------------------------------------------------

  void _paintCycleFills(Canvas canvas) {
    if (fig.segments.isEmpty) return;
    final adj = <int, List<int>>{};
    for (var i = 0; i < fig.points.length; i++) {
      adj[i] = [];
    }
    for (final s in fig.segments) {
      if (s.hidden || s.isNone) continue;
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
      if (c.isAnimateMode &&
          !_visibleAt(fig, compPts.first, c.currentTime)) {
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
        if (ordered.length >= 3 &&
            ordered.first == ordered.last) {
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
          if (entry.filled) {
            final overColor = _colorOverrideAt(fig, ordered.first, c.currentTime);
            final fillColor = parseHexColor(overColor) ?? parseHexColor(entry.fillColor) ?? const Color(0xFFD1D5DB);
            final path = _cyclePath(pts);
            canvas.drawPath(path, Paint()..color = fillColor);
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
          (pt: seed, prev: -1, path: [seed])
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
                if (entry.filled) {
                  final overColor = _colorOverrideAt(fig, seed, c.currentTime);
                  final fillColor = parseHexColor(overColor) ?? parseHexColor(entry.fillColor) ??
                      const Color(0xFFD1D5DB);
                  final pts = [...cur.path, seed];
                  final path = _cyclePath(pts);
                  canvas.drawPath(path, Paint()..color = fillColor);
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

  Path _cyclePath(List<int> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(fig.points[pts[0]].x, fig.points[pts[0]].y);
    for (var j = 0; j < pts.length; j++) {
      final next = (j + 1) % pts.length;
      final seg = _segmentBetween(pts[j], pts[next]);
      if (seg != null && seg.curved && seg.controlDX != null && seg.controlDY != null) {
        final mx = (fig.points[pts[j]].x + fig.points[pts[next]].x) / 2;
        final my = (fig.points[pts[j]].y + fig.points[pts[next]].y) / 2;
        path.quadraticBezierTo(
          mx + seg.controlDX!,
          my + seg.controlDY!,
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

  void _paintSegments(Canvas canvas) {
    final sorted = fig.segmentsInDrawOrder();
    for (final seg in sorted) {
      if (seg.hidden || seg.isNone) continue;
      if (c.isAnimateMode && !_visibleAt(fig, seg.point1Index, c.currentTime)) {
        continue;
      }
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];

      final opacity = _opacityAt(fig, seg.point1Index, c.currentTime);

      final overColor = _colorOverrideAt(fig, seg.point1Index, c.currentTime);

      if (seg.type == 'line') {
        final baseColor = parseHexColor(overColor ?? seg.color) ?? const Color(0xFFD1D5DB);
        final paint = Paint()
          ..color = baseColor.withOpacity(baseColor.opacity * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = seg.width <= 0 ? 3 : seg.width
          ..strokeCap = _capFor(seg.lineCap);
        _drawSegmentLine(canvas, paint, seg, p1, p2);
      } else if (seg.type == 'circle') {
        double mx = (p1.x + p2.x) / 2;
        double my = (p1.y + p2.y) / 2;
        if (seg.curved) {
          final cpx = seg.controlDX != null
              ? mx + seg.controlDX!
              : mx + (-(p2.y - p1.y) * seg.curvature);
          final cpy = seg.controlDY != null
              ? my + seg.controlDY!
              : my + ((p2.x - p1.x) * seg.curvature);
          mx = (p1.x + p2.x) / 4 + cpx / 2;
          my = (p1.y + p2.y) / 4 + cpy / 2;
        }
        final r = math.max(
          math.sqrt((p2.x - p1.x) * (p2.x - p1.x) +
                  (p2.y - p1.y) * (p2.y - p1.y)) /
              2,
          1.0,
        );
        if (seg.filled) {
          final baseColor = parseHexColor(overColor) ??
              parseHexColor(seg.fillColor) ??
              parseHexColor(seg.color) ??
              const Color(0xFFD1D5DB);
          final paint = Paint()..color = baseColor.withOpacity(baseColor.opacity * opacity);
          canvas.drawCircle(Offset(mx, my), r, paint);
        }
        final strokeColor = parseHexColor(overColor ?? seg.color) ?? const Color(0xFFD1D5DB);
        canvas.drawCircle(
          Offset(mx, my),
          r,
          Paint()
            ..color = strokeColor.withOpacity(strokeColor.opacity * opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = seg.width <= 0 ? 3 : seg.width,
        );
      } else if (seg.type == 'image') {
        _paintImageSegment(canvas, seg, p1, p2, opacity);
      }
    }
  }

  void _drawSegmentLine(Canvas canvas, Paint paint, Segment seg, Point2 p1, Point2 p2) {
    final path = Path()..moveTo(p1.x, p1.y);
    if (seg.curved) {
      final mx = (p1.x + p2.x) / 2;
      final my = (p1.y + p2.y) / 2;
      final cpx = seg.controlDX != null
          ? mx + seg.controlDX!
          : mx + (-(p2.y - p1.y) * seg.curvature);
      final cpy = seg.controlDY != null
          ? my + seg.controlDY!
          : my + ((p2.x - p1.x) * seg.curvature);
      path.quadraticBezierTo(cpx, cpy, p2.x, p2.y);
    } else {
      path.lineTo(p2.x, p2.y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintImageSegment(Canvas canvas, Segment seg, Point2 p1, Point2 p2, double opacity) {
    int imageIndex = seg.activeImageIndex;
    if (c.isAnimateMode) {
      imageIndex = fig.getSegmentImageIndex(seg.id, c.currentTime) ?? imageIndex;
    }
    String? imageData = seg.imageDataList.isNotEmpty && imageIndex >= 0 && imageIndex < seg.imageDataList.length
        ? seg.imageDataList[imageIndex]
        : null;

    final image = imageFor(imageData);
    if (image == null) return;
    double mx = (p1.x + p2.x) / 2;
    double my = (p1.y + p2.y) / 2;
    if (seg.curved) {
      final cpx = seg.controlDX != null
          ? mx + seg.controlDX!
          : mx + (-(p2.y - p1.y) * seg.curvature);
      final cpy = seg.controlDY != null
          ? my + seg.controlDY!
          : my + ((p2.x - p1.x) * seg.curvature);
      mx = (p1.x + p2.x) / 4 + cpx / 2;
      my = (p1.y + p2.y) / 4 + cpy / 2;
    }
    final ox = seg.imageOffsetX;
    final oy = seg.imageOffsetY;
    final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final rotate = segAngle + seg.imageRotate * math.pi / 180;
    final cx = mx + ox;
    final cy = my + oy;
    final size = _resolveImageSize(seg, image);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotate);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.restore();
  }

  Size _resolveImageSize(Segment seg, ui.Image image) {
    var w = seg.imageWidth is num
        ? (seg.imageWidth as num).toDouble()
        : 100.0;
    var h = seg.imageHeight is num
        ? (seg.imageHeight as num).toDouble()
        : 100.0;
    final wAuto = seg.imageWidth == 'auto';
    final hAuto = seg.imageHeight == 'auto';
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
    for (final seg in fig.segments) {
      if (!seg.curved || seg.controlDX == null) continue;
      if (c.isAnimateMode && !_visibleAt(fig, seg.point1Index, c.currentTime)) {
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
      final cx = mx + seg.controlDX!;
      final cy = my + seg.controlDY!;

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
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()..color = const Color(0xFFEC4899),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
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
      final sel = i == c.selectedPointIndex;
      final r = (sel ? 7 : 5) / z;
      final isRoot = fig.rootIndices.contains(i);
      final Color fill;
      if (sel) {
        fill = const Color(0xFFFACC15);
      } else if (pt.isAttached) {
        fill = const Color(0xFFF97316); // orange for attached pivot
      } else if (isRoot) {
        fill = const Color(0xFFEF4444);
      } else if (c.pointModes[i] == 'static') {
        fill = const Color(0xFF6B7280);
      } else {
        fill = const Color(0xFF0EA5E9);
      }
      canvas.drawCircle(
        Offset(pt.x, pt.y),
        r,
        Paint()..color = fill,
      );
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
    final roots = f.rootIndices.isNotEmpty ? f.rootIndices : [0];
    var root = roots.first;
    outer:
    for (final r in roots) {
      final visited = <int>{r};
      final queue = <int>[r];
      while (queue.isNotEmpty) {
        final idx = queue.removeAt(0);
        if (idx == pointIdx) {
          root = r;
          break outer;
        }
        for (final s in f.segments) {
          final other = s.point1Index == idx
              ? s.point2Index
              : s.point2Index == idx
                  ? s.point1Index
                  : -1;
          if (other >= 0 && !visited.contains(other)) {
            visited.add(other);
            queue.add(other);
          }
        }
      }
    }
    return f.getFigureVisibility(root, t);
  }

  double _opacityAt(Figure f, int pointIdx, double t) {
    if (pointIdx < 0 || pointIdx >= f.points.length) return 1.0;
    final roots = f.rootIndices.isNotEmpty ? f.rootIndices : [0];
    var root = roots.first;
    outer:
    for (final r in roots) {
      final visited = <int>{r};
      final queue = <int>[r];
      while (queue.isNotEmpty) {
        final idx = queue.removeAt(0);
        if (idx == pointIdx) {
          root = r;
          break outer;
        }
        for (final s in f.segments) {
          final other = s.point1Index == idx
              ? s.point2Index
              : s.point2Index == idx
                  ? s.point1Index
                  : -1;
          if (other >= 0 && !visited.contains(other)) {
            visited.add(other);
            queue.add(other);
          }
        }
      }
    }
    return f.getFigureOpacity(root, t);
  }

  String? _colorOverrideAt(Figure f, int pointIdx, double t) {
    if (!c.isAnimateMode) return null;
    if (pointIdx < 0 || pointIdx >= f.points.length) return null;
    final roots = f.rootIndices.isNotEmpty ? f.rootIndices : [0];
    var root = roots.first;
    outer:
    for (final r in roots) {
      final visited = <int>{r};
      final queue = <int>[r];
      while (queue.isNotEmpty) {
        final idx = queue.removeAt(0);
        if (idx == pointIdx) {
          root = r;
          break outer;
        }
        for (final s in f.segments) {
          final other = s.point1Index == idx
              ? s.point2Index
              : s.point2Index == idx
                  ? s.point1Index
                  : -1;
          if (other >= 0 && !visited.contains(other)) {
            visited.add(other);
            queue.add(other);
          }
        }
      }
    }
    return f.getFigureColorOverride(root, t);
  }

  @override
  bool shouldRepaint(covariant FigureCanvasPainter oldDelegate) {
    return oldDelegate.imageVersion != imageVersion ||
        oldDelegate.controller != controller ||
        oldDelegate.palette != palette;
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
    double hw, double hh, double rotate, double cx, double cy) {
  final cosR = math.cos(rotate), sinR = math.sin(rotate);
  Offset tr(Offset local) => Offset(
        cx + local.dx * cosR - local.dy * sinR,
        cy + local.dx * sinR + local.dy * cosR,
      );
  const corners = [
    Offset(1, -1), Offset(0, -1), Offset(-1, -1), Offset(-1, 0),
    Offset(-1, 1), Offset(0, 1), Offset(1, 1), Offset(1, 0),
  ];
  final pts = corners
      .map((o) => tr(Offset(o.dx * hw, o.dy * hh)))
      .toList();
  final rotLocal = Offset(0, -(hh + 28));
  pts.add(tr(rotLocal));
  return pts;
}
