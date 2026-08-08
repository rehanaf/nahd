import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/models/figure.dart';
import '../../../core/models/figure_animation.dart';
import '../../../core/models/segment.dart';
import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';

part 'figure_canvas_types.dart';
part 'figure_canvas_painter.dart';
part 'tools/select_join_tool.dart';
part 'tools/point_modify_tool.dart';
part 'tools/transform_tools.dart';
part 'tools/curve_tool.dart';
part 'tools/draw_tool.dart';
part 'tools/asset_tool.dart';

/// The interactive canvas, the Flutter analog of `FigureCanvasArea.tsx`.
class FigureCanvas extends StatefulWidget {
  final EditorController controller;

  const FigureCanvas({super.key, required this.controller});

  @override
  State<FigureCanvas> createState() => _FigureCanvasState();
}

class _FigureCanvasState extends State<FigureCanvas> {
  final _drag = _DragState();
  int? _lastPt;

  Size _canvasSize = const Size(800, 600);

  // Image cache for image segments.
  final Map<String, ui.Image> _imageCache = {};
  final Map<String, bool> _imagePending = {};
  int _imageVersion = 0;

  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartZoom = 0.8;
  Offset? _pinchStartMid;
  Offset? _pinchStartCam;

  @override
  void initState() {
    super.initState();
    _prefetchImages();
  }

  @override
  void didUpdateWidget(covariant FigureCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastPt = null;
      _prefetchImages();
    }
  }

  void _prefetchImages() {
    for (final seg in widget.controller.figure.segments) {
      if (seg.isImage && seg.imageData != null) {
        _decodeImage(seg.imageData!);
      }
    }
  }

  Future<void> _decodeImage(String dataUri) async {
    if (_imageCache.containsKey(dataUri) || _imagePending[dataUri] == true) {
      return;
    }
    _imagePending[dataUri] = true;
    try {
      final comma = dataUri.indexOf(',');
      final b64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imageCache[dataUri] = frame.image;
        _imageVersion++;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _imagePending[dataUri] = false;
        });
      }
    }
  }

  ui.Image? _imageFor(String? dataUri) {
    if (dataUri == null) return null;
    if (!_imageCache.containsKey(dataUri)) _decodeImage(dataUri);
    return _imageCache[dataUri];
  }

  // -------------------------------------------------------------------------
  // Coordinate helpers
  // -------------------------------------------------------------------------

  Offset _screenToWorld(Offset s, Size size, CameraTransform cam) =>
      Offset(
        (s.dx - size.width / 2 - cam.x) / cam.zoom,
        (s.dy - size.height / 2 - cam.y) / cam.zoom,
      );

  bool _visibleAt(Figure fig, int pointIdx, double t) {
    if (pointIdx < 0 || pointIdx >= fig.points.length) return true;
    final roots = fig.rootIndices.isNotEmpty ? fig.rootIndices : [0];
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
        for (final s in fig.segments) {
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
    return fig.getFigureVisibility(root, t);
  }

  double _opacityAt(Figure fig, int pointIdx, double t) {
    if (pointIdx < 0 || pointIdx >= fig.points.length) return 1.0;
    final roots = fig.rootIndices.isNotEmpty ? fig.rootIndices : [0];
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
        for (final s in fig.segments) {
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
    return fig.getFigureOpacity(root, t);
  }

  int _hitTestPoint(Offset w) {
    final fig = widget.controller.figure;
    final z = widget.controller.camera.zoom;
    final threshold = 15 / z;
    final animate = widget.controller.isAnimateMode;
    for (var i = 0; i < fig.points.length; i++) {
      if (animate &&
          !_visibleAt(fig, i, widget.controller.currentTime)) {
        continue;
      }
      final dx = fig.points[i].x - w.dx;
      final dy = fig.points[i].y - w.dy;
      if (math.sqrt(dx * dx + dy * dy) < threshold) return i;
    }
    return -1;
  }

  /// Returns the figure root that owns [pointIdx] (the first root whose
  /// connected component contains it).
  int _rootOfPoint(Figure fig, int pointIdx) {
    for (final r in fig.getFigureRoots()) {
      if (r >= 0 &&
          r < fig.points.length &&
          fig.connectedComponent(r).contains(pointIdx)) {
        return r;
      }
    }
    return fig.getFigureRoots().isEmpty ? 0 : fig.getFigureRoots().first;
  }

  String? _hitTestSegment(Offset w) {
    final fig = widget.controller.figure;
    final z = widget.controller.camera.zoom;
    final threshold = 10 / z;
    for (var i = fig.segments.length - 1; i >= 0; i--) {
      final seg = fig.segments[i];
      if (seg.hidden) continue;
      if (seg.point1Index < 0 ||
          seg.point1Index >= fig.points.length ||
          seg.point2Index < 0 ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];
      if (seg.type == 'line' || seg.isNone) {
        final dx = p2.x - p1.x;
        final dy = p2.y - p1.y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 0.01) continue;
        var t = ((w.dx - p1.x) * dx + (w.dy - p1.y) * dy) / (len * len);
        t = t.clamp(0.0, 1.0);
        final px = p1.x + t * dx;
        final py = p1.y + t * dy;
        if (math.sqrt((w.dx - px) * (w.dx - px) + (w.dy - py) * (w.dy - py)) <
            threshold) {
          return seg.id;
        }
      } else if (seg.type == 'circle') {
        final mx = (p1.x + p2.x) / 2;
        final my = (p1.y + p2.y) / 2;
        final dx2 = p2.x - p1.x;
        final dy2 = p2.y - p1.y;
        final r = math.sqrt(dx2 * dx2 + dy2 * dy2) / 2;
        final dist = math.sqrt((w.dx - mx) * (w.dx - mx) + (w.dy - my) * (w.dy - my));
        if ((dist - r).abs() < threshold) return seg.id;
      } else if (seg.type == 'image') {
        if (seg.imageData == null) continue;
        final meta = _imageMeta(seg.imageData!);
        final size = _resolveImageSize(seg, meta);
        final mx = (p1.x + p2.x) / 2;
        final my = (p1.y + p2.y) / 2;
        final ox = seg.imageOffsetX;
        final oy = seg.imageOffsetY;
        final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
        final rotate = segAngle + seg.imageRotate * math.pi / 180;
        final cx = mx + ox;
        final cy = my + oy;
        final dx = w.dx - cx;
        final dy = w.dy - cy;
        final cosR = math.cos(rotate);
        final sinR = math.sin(rotate);
        final lx = dx * cosR + dy * sinR;
        final ly = -dx * sinR + dy * cosR;
        if (lx >= -size.width / 2 &&
            lx <= size.width / 2 &&
            ly >= -size.height / 2 &&
            ly <= size.height / 2) {
          return seg.id;
        }
      }
    }
    return null;
  }

  ui.Image? _imageMeta(String uri) => _imageCache[uri];

  Size _resolveImageSize(Segment seg, ui.Image? meta) {
    var w = seg.imageWidth is num ? (seg.imageWidth as num).toDouble() : 100.0;
    var h = seg.imageHeight is num ? (seg.imageHeight as num).toDouble() : 100.0;
    final wAuto = seg.imageWidth == 'auto';
    final hAuto = seg.imageHeight == 'auto';
    if (meta != null && meta.width > 0 && meta.height > 0) {
      final ar = meta.width / meta.height;
      if (wAuto && hAuto) {
        w = 100;
        h = 100 / ar;
      } else if (wAuto) {
        w = h * ar;
      } else if (hAuto) {
        h = w / ar;
      }
    } else {
      if (wAuto) w = 100;
      if (hAuto) h = 100;
    }
    return Size(w, h);
  }

  List<int> _findConnectedPoints(Figure fig, int pivotIdx) {
    final visited = <int>{pivotIdx};
    final queue = <int>[pivotIdx];
    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      for (final s in fig.segments) {
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
    return visited.where((i) => i != pivotIdx).toList();
  }

  // -------------------------------------------------------------------------
  // Gesture handling
  // -------------------------------------------------------------------------



  // =========================================================================
  // Pointer / pinch plumbing
  // =========================================================================
  void _handlePointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length > 1) {
      _drag.reset();
      _beginPinch();
      return;
    }
    _handleTouchStart(e.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length > 1) {
      if (_pinchStartDist == null) _beginPinch();
      _updatePinch();
      return;
    }
    if (prev != null && _pinchStartDist != null) {
      // Returned to single pointer after pinch.
      _pinchStartDist = null;
      _pinchStartMid = null;
    }
    _handleTouchMove(e.localPosition);
  }

  void _handlePointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinchStartDist != null && _pointers.length < 2) {
      _pinchStartDist = null;
      _pinchStartMid = null;
    }
    if (_pointers.isEmpty) {
      _handleTouchEnd();
    }
  }

  void _beginPinch() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return;
    final cam = widget.controller.camera;
    _pinchStartDist = (pts[0] - pts[1]).distance;
    _pinchStartZoom = cam.zoom;
    _pinchStartMid = (pts[0] + pts[1]) / 2;
    _pinchStartCam = Offset(cam.x, cam.y);
  }

  void _updatePinch() {
    final pts = _pointers.values.toList();
    if (pts.length < 2 || _pinchStartDist == null) return;
    final dist = (pts[0] - pts[1]).distance;
    final mid = (pts[0] + pts[1]) / 2;
    final zoom =
        (_pinchStartZoom * dist / _pinchStartDist!).clamp(0.1, 5.0);
    // Zoom toward the pinch midpoint.
    final mx = _pinchStartMid!.dx;
    final my = _pinchStartMid!.dy;
    final wx = (mx - _canvasSize.width / 2 - _pinchStartCam!.dx) /
        _pinchStartZoom;
    final wy = (my - _canvasSize.height / 2 - _pinchStartCam!.dy) /
        _pinchStartZoom;
    final newX = mid.dx - _canvasSize.width / 2 - wx * zoom;
    final newY = mid.dy - _canvasSize.height / 2 - wy * zoom;
    widget.controller.setCamera(CameraTransform(
      x: newX,
      y: newY,
      zoom: zoom,
    ));
  }

  void _handleTouchStart(Offset loc) {
    final fig = widget.controller.figure;
    final cam = widget.controller.camera;
    final w = _screenToWorld(loc, _canvasSize, cam);
    final tool = widget.controller.activeTool;

    if (widget.controller.isPlaying) {
      widget.controller.stopPlayback();
    }

    // Delegate to tools
    handleSelectJoinStart(w, tool, fig);
    if (_drag.active) return;

    handlePointModifyStart(w, tool, fig);
    if (_drag.active) return;

    handleTransformStart(w, tool, fig, cam);
    if (_drag.active) return;

    handleCurveStart(w, tool, fig, cam);
    if (_drag.active) return;

    handleAssetStart(w, tool, fig);
    if (_drag.active) return;

    handleDrawStart(w, tool, fig);
    if (_drag.active) return;

    // Default: pan.
    _drag
      ..reset()
      ..isPan = true
      ..startPanX = loc.dx
      ..startPanY = loc.dy
      ..startCamX = cam.x
      ..startCamY = cam.y;
  }

  void _captureAnchorForPoint(Figure fig, int ptIdx, {bool all = false}) {
    if (!widget.controller.isAnchorMode) return;
    _drag.anchorImgCenter.clear();
    _drag.anchorImgRot.clear();
    for (final s in fig.segments) {
      if (!s.isImage) continue;
      if (!all &&
          s.point1Index != ptIdx &&
          s.point2Index != ptIdx) {
        continue;
      }
      final p1 = fig.points[s.point1Index];
      final p2 = fig.points[s.point2Index];
      final midX = (p1.x + p2.x) / 2;
      final midY = (p1.y + p2.y) / 2;
      final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
      _drag.anchorImgCenter[s.id] = Point2(
        midX + s.imageOffsetX,
        midY + s.imageOffsetY,
      );
      _drag.anchorImgRot[s.id] = segAngle * 180 / math.pi + s.imageRotate;
    }
  }

  Segment? _segmentTouching(Figure fig, int ptIdx) {
    for (final s in fig.segments) {
      if (s.point1Index == ptIdx || s.point2Index == ptIdx) return s;
    }
    return null;
  }

  void _handleTouchMove(Offset loc) {
    final d = _drag;
    if (d.isPan) {
      widget.controller.setCamera(CameraTransform(
        x: d.startCamX + (loc.dx - d.startPanX),
        y: d.startCamY + (loc.dy - d.startPanY),
        zoom: widget.controller.camera.zoom,
      ));
      return;
    }
    if (!d.active) return;
    final fig = widget.controller.figure;
    final cam = widget.controller.camera;
    final w = _screenToWorld(loc, _canvasSize, cam);

    if (d.assetDrag) {
      handleAssetMove(w, fig, d);
      return;
    }

    if (d.isPoint && d.ptIdx >= 0 && d.ptIdx < fig.points.length) {
      final pt = fig.points[d.ptIdx];
      final dx = w.dx - d.startX;
      final dy = w.dy - d.startY;
      if (d.connPts.isNotEmpty) {
        for (final i in d.connPts) {
          final init = d.fkInit[i];
          if (init != null) {
            fig.points[i].x = init.x + dx;
            fig.points[i].y = init.y + dy;
          }
        }
      } else {
        pt.x = d.startPtX + dx;
        pt.y = d.startPtY + dy;
      }
      if (d.creating && fig.segments.isNotEmpty) {
        final seg = fig.segments.last;
        if (seg.point1Index >= 0 && seg.point1Index < fig.points.length) {
          final p1 = fig.points[seg.point1Index];
          p1.x = d.anchorX;
          p1.y = d.anchorY;
        }
      }

      if (widget.controller.isAnchorMode &&
          d.anchorImgCenter.isNotEmpty) {
        for (final e in d.anchorImgCenter.entries) {
          final seg = fig.getSegment(e.key);
          if (seg == null) continue;
          if (seg.point1Index >= fig.points.length ||
              seg.point2Index >= fig.points.length) {
            continue;
          }
          final p1 = fig.points[seg.point1Index];
          final p2 = fig.points[seg.point2Index];
          final midX = (p1.x + p2.x) / 2;
          final midY = (p1.y + p2.y) / 2;
          seg.imageOffsetX = e.value.x - midX;
          seg.imageOffsetY = e.value.y - midY;
          final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
          seg.imageRotate =
              (d.anchorImgRot[seg.id] ?? segAngle * 180 / math.pi) -
              segAngle * 180 / math.pi;
        }
        widget.controller.forceUpdate();
      }
      widget.controller.forceUpdate();
    }

    handleSelectJoinMove(fig, d, w);

    if (d.isSegment && d.segId != null) {
      final seg = fig.getSegment(d.segId!);
      if (seg != null) {
        if (seg.point1Index < fig.points.length &&
            seg.point2Index < fig.points.length) {
          final p1 = fig.points[seg.point1Index];
          final p2 = fig.points[seg.point2Index];
          p1.x += w.dx - d.startX;
          p1.y += w.dy - d.startY;
          p2.x += w.dx - d.startX;
          p2.y += w.dy - d.startY;
          d.startX = w.dx;
          d.startY = w.dy;
          widget.controller.forceUpdate();
        }
      }
    }

    if (d.curving && d.segId != null) {
      final seg = fig.getSegment(d.segId!);
      if (seg != null) {
        // Control is stored as an offset from the segment midpoint; track the
        // pointer by starting from the grabbed offset and adding the mouse
        // delta so the handle follows 1:1.
        seg.controlDX = d.startPtX + (w.dx - d.startX);
        seg.controlDY = d.startPtY + (w.dy - d.startY);
        widget.controller.forceUpdate();
      }
    }

    if (d.rotating && d.connPts.isNotEmpty) {
      // Center: either a point pivot or an explicit centroid (pivot == -1).
      final double px, py;
      if (d.pivot >= 0 && d.pivot < fig.points.length) {
        px = fig.points[d.pivot].x;
        py = fig.points[d.pivot].y;
      } else {
        px = d.pivotCenterX;
        py = d.pivotCenterY;
      }
      final angleDelta = math.atan2(w.dy - py, w.dx - px) - d.startAngle;
      for (var i = 0; i < d.connPts.length; i++) {
        if (d.connPts[i] == d.pivot) continue;
        final a = d.initAngles[i] + angleDelta;
        fig.points[d.connPts[i]].x = px + math.cos(a) * d.initDists[i];
        fig.points[d.connPts[i]].y = py + math.sin(a) * d.initDists[i];
      }
      _rotateCurveControls(fig, d, angleDelta);
      widget.controller.forceUpdate();
    }

    if (d.stretching && d.pivot >= 0) {
      final rx = fig.points[d.pivot].x;
      final ry = fig.points[d.pivot].y;
      final curDist =
          math.sqrt((w.dx - rx) * (w.dx - rx) + (w.dy - ry) * (w.dy - ry));
      final factor = curDist / d.startDist;
      for (var i = 0; i < d.connPts.length; i++) {
        final idx = d.connPts[i];
        if (idx < 0 || idx >= fig.points.length) continue;
        fig.points[idx].x = rx + math.cos(d.initAngles[i]) * d.initDists[i] * factor;
        fig.points[idx].y = ry + math.sin(d.initAngles[i]) * d.initDists[i] * factor;
      }
      _scaleCurveControls(fig, d, factor);

      d.initSegs.forEach((segId, initVal) {
        final seg = fig.getSegment(segId);
        if (seg != null) {
          seg.width = initVal.width * factor;
          if (seg.imageWidth is num) {
            seg.imageWidth = initVal.imageWidth * factor;
          }
          if (seg.imageHeight is num) {
            seg.imageHeight = initVal.imageHeight * factor;
          }
        }
      });

      widget.controller.forceUpdate();
    }

    if (d.connPts.length > 1 &&
        d.initAngles.length > 1 &&
        !d.rotating &&
        !d.stretching) {
      final cx = d.startPtX;
      final cy = d.startPtY;
      final angleDelta = math.atan2(w.dy - cy, w.dx - cx) - d.startAngle;
      for (var i = 0; i < d.connPts.length; i++) {
        final a = d.initAngles[i] + angleDelta;
        fig.points[d.connPts[i]].x = cx + math.cos(a) * d.initDists[i];
        fig.points[d.connPts[i]].y = cy + math.sin(a) * d.initDists[i];
      }
      widget.controller.forceUpdate();
    }

    // Animation recording.
    if (widget.controller.isAnimateMode && !d.creating) {
      final recPts = <int>{};
      if (d.connPts.isNotEmpty) {
        recPts.addAll(d.connPts);
      } else if (d.isPoint && d.ptIdx >= 0) {
        recPts.add(d.ptIdx);
      }
      if (d.isSegment && d.segId != null) {
        final seg = fig.getSegment(d.segId!);
        if (seg != null) {
          recPts.add(seg.point1Index);
          recPts.add(seg.point2Index);
        }
      }
      if (recPts.isNotEmpty) {
        final anim = widget.controller.ensureAnimation();
        for (final i in recPts) {
          if (i < fig.points.length) {
            final p = fig.points[i];
            anim.setPointPose(widget.controller.currentTime, i, p.x, p.y);
          }
        }
        if (anim.duration > widget.controller.duration) {
          widget.controller.setDuration(anim.duration);
        }
      }
    }
  }

  void _rotateCurveControls(Figure fig, _DragState d, double angleDelta) {
    final npSet = d.connPts.toSet();
    for (final s in fig.segments) {
      if (!s.curved || s.controlDX == null || s.controlDY == null) continue;
      if (npSet.contains(s.point1Index) && npSet.contains(s.point2Index)) {
        final orig = d.fkCtrl[s.id];
        if (orig == null) continue;
        final cosA = math.cos(angleDelta);
        final sinA = math.sin(angleDelta);
        s.controlDX = orig.dx * cosA - orig.dy * sinA;
        s.controlDY = orig.dx * sinA + orig.dy * cosA;
      }
    }
  }

  void _scaleCurveControls(Figure fig, _DragState d, double factor) {
    final npSet = d.connPts.toSet();
    for (final s in fig.segments) {
      if (!s.curved || s.controlDX == null || s.controlDY == null) continue;
      if (npSet.contains(s.point1Index) && npSet.contains(s.point2Index)) {
        final orig = d.fkCtrl[s.id];
        if (orig == null) continue;
        s.controlDX = orig.dx * factor;
        s.controlDY = orig.dy * factor;
      }
    }
  }



  /// Join/unjoin drag handling for the [EditorTool.join] tool.
  ///
  /// * Join: when the dragged point gets within a small threshold of another
  ///   point that it is not already connected to, the two points merge and
  ///   the target's root is kept (the moved point's root is dropped).
  /// * Unjoin: when a point shared by two segments is dragged apart, the
  ///   dragged side is duplicated into a new point/root so the joint splits.
  void _handleJoinMove(Figure fig, _DragState d, Offset w) {
    final z = widget.controller.camera.zoom;
    final threshold = 15 / z;
    final pt = fig.points[d.ptIdx];
    final touching = fig.segments.where(
      (s) => s.point1Index == d.ptIdx || s.point2Index == d.ptIdx,
    ).toList();

    if (touching.length < 2) {
      // JOIN: a free endpoint dragged onto another point.
      for (var i = 0; i < fig.points.length; i++) {
        if (i == d.ptIdx) continue;
        final o = fig.points[i];
        final dist = math.sqrt(
            (o.x - pt.x) * (o.x - pt.x) + (o.y - pt.y) * (o.y - pt.y));
        if (dist < threshold) {
          final alreadyConnected = fig.segments.any((s) =>
              (s.point1Index == d.ptIdx && s.point2Index == i) ||
              (s.point1Index == i && s.point2Index == d.ptIdx));
          if (alreadyConnected) continue;
          widget.controller.joinPoints(d.ptIdx, i);
          d.jointDone = true;
          d.active = false;
          return;
        }
      }
      return;
    }

    // UNJOIN: a shared joint dragged apart from its neighbours. Split the
    // segment that is most perpendicular/opposite to the drag direction so
    // the dragged side keeps moving and the other side keeps a copy.
    final dx = pt.x - d.startPtX;
    final dy = pt.y - d.startPtY;
    final movedDist = math.sqrt(dx * dx + dy * dy);
    if (movedDist < threshold) return;

    Segment? detachSeg;
    double bestScore = double.negativeInfinity;
    for (final s in touching) {
      final other = s.point1Index == d.ptIdx
          ? s.point2Index
          : s.point1Index;
      if (other < 0 || other >= fig.points.length) continue;
      final o = fig.points[other];
      final ox = o.x - d.startPtX;
      final oy = o.y - d.startPtY;
      final len = math.sqrt(ox * ox + oy * oy);
      if (len < 0.001) continue;
      // Alignment of the neighbour direction with the drag direction.
      final score = (ox * dx + oy * dy) / (len * math.sqrt(dx * dx + dy * dy));
      if (score > bestScore) {
        bestScore = score;
        detachSeg = s;
      }
    }
    if (detachSeg == null) return;
    final otherIdx = detachSeg.point1Index == d.ptIdx
        ? detachSeg.point2Index
        : detachSeg.point1Index;
    widget.controller.splitJoint(
        d.ptIdx, otherIdx, d.startPtX, d.startPtY);
    d.jointDone = true;
  }

  void _handleAttachMove(Figure fig, _DragState d, Offset w) {
    final z = widget.controller.camera.zoom;
    final threshold = 15 / z;
    final pt = fig.points[d.ptIdx];
    final draggedComp = fig.connectedComponent(d.ptIdx);
    
    // Only allow attaching the ROOT of the figure, or any point?
    // User: "mirip seperti join tapi drag pivot hanya move, dan yg di drag menjadi attachment untuk titik tujuannya"
    // Usually it attaches the root. But we'll just use d.ptIdx.
    
    for (var i = 0; i < fig.points.length; i++) {
      if (i == d.ptIdx) continue;
      // Constraint: "hanya bisa attach jika di figure yg berbeda, tadi tidak bisa attach ke segment lain yg masih 1 root"
      if (draggedComp.contains(i)) continue;
      
      final o = fig.points[i];
      final dist = math.sqrt(
          (o.x - pt.x) * (o.x - pt.x) + (o.y - pt.y) * (o.y - pt.y));
      if (dist < threshold) {
        // They are close enough, attach!
        // Joining merges them structurally.
        widget.controller.joinPoints(d.ptIdx, i);
        d.jointDone = true;
        d.active = false;
        widget.controller.setTool(EditorTool.rotate); // revert tool
        return;
      }
    }
  }

  void _handleTouchEnd() {
    final wasCreating = _drag.creating;
    final wasDragging = _drag.active || _drag.isPan;
    final wasAsset = _drag.assetDrag;
    _drag.reset();
    _lastPt = null;
    if (wasCreating) widget.controller.pushHistory();
    if (wasAsset) widget.controller.pushHistory();
    if (wasDragging) {
      widget.controller.pushHistory();
      widget.controller.forceUpdate();
    }
  }
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        _prefetchImages();
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerUp,
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final cam = widget.controller.camera;
              final zoomDelta = -pointerSignal.scrollDelta.dy * 0.001;
              final newZoom = (cam.zoom + zoomDelta).clamp(0.1, 5.0);
              widget.controller.setCamera(CameraTransform(
                x: cam.x,
                y: cam.y,
                zoom: newZoom,
              ));
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasSize = constraints.biggest;
              final palette = Theme.of(context).appColors;
              return CustomPaint(
                size: Size.infinite,
                painter: FigureCanvasPainter(
                  controller: widget.controller,
                  palette: palette,
                  imageFor: _imageFor,
                  imageVersion: _imageVersion,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

