import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

  Segment? _selectedAssetSegment() {
    final id = widget.controller.assetSegmentId ??
        widget.controller.selectedSegmentId;
    if (id == null) return null;
    final seg = widget.controller.figure.getSegment(id);
    if (seg == null || !seg.isImage) return null;
    return seg;
  }

  bool _handleAssetStart(Offset w, Figure fig) {
    // If there's a selected image segment, try to grab a handle first.
    final seg = _selectedAssetSegment();
    if (seg != null &&
        seg.point1Index < fig.points.length &&
        seg.point2Index < fig.points.length) {
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];
      final image = _imageFor(seg.imageData);
      final size = _resolveImageSize(seg, image);
      final mx = (p1.x + p2.x) / 2 + seg.imageOffsetX;
      final my = (p1.y + p2.y) / 2 + seg.imageOffsetY;
      final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
      final rotate = segAngle + seg.imageRotate * math.pi / 180;
      final handles = _assetHandles(size.width / 2, size.height / 2, rotate, mx, my);

final z = widget.controller.camera.zoom;
      const hitR = 12.0 / 1.0; // in world units; scaled below
      // Find grabbed handle.
      for (var i = 0; i < handles.length; i++) {
        final dx = w.dx - handles[i].dx;
        final dy = w.dy - handles[i].dy;
        if (dx * dx + dy * dy < (hitR * hitR) / (z * z)) {
          final isRot = i == 8;
          _drag
            ..reset()
            ..active = true
            ..assetDrag = true
            ..assetOp = isRot ? 'rotate' : 'resize'
            ..assetHandle = i
            ..startOx = seg.imageOffsetX
            ..startOy = seg.imageOffsetY
            ..startRot = seg.imageRotate
            ..startW = size.width
            ..startH = size.height
            ..assetCenterX = mx
            ..assetCenterY = my
            ..startAngle = math.atan2(w.dy - my, w.dx - mx)
            ..startX = w.dx
            ..startY = w.dy;
          widget.controller.selectAssetSegment(seg.id);
          widget.controller.forceUpdate();
          return true;
        }
      }
      // Check if tap is inside the box -> move.
      final inside = _pointInRotatedRect(
        w,
        handles.take(8).toList(),
        mx,
        my,
        rotate,
      );
      if (inside) {
        _drag
          ..reset()
          ..active = true
          ..assetDrag = true
          ..assetOp = 'move'
          ..startOx = seg.imageOffsetX
          ..startOy = seg.imageOffsetY
          ..startX = w.dx
          ..startY = w.dy;
        widget.controller.selectAssetSegment(seg.id);
        widget.controller.forceUpdate();
        return true;
      }
    }

    // Otherwise, try to select an image segment under the pointer.
    final hit = _hitTestImageSegment(w, fig);
    if (hit != null) {
      widget.controller.selectAssetSegment(hit);
      widget.controller.forceUpdate();
      return true;
    }
    // Nothing grabbed: let the caller fall through to the normal rig tool so
    // rig editing still works in asset mode.
    return false;
  }

  bool _pointInRotatedRect(
      Offset w, List<Offset> corners, double cx, double cy, double rotate) {
    if (corners.length < 4) return false;
    final cosR = math.cos(rotate), sinR = math.sin(rotate);
    final dx = w.dx - cx, dy = w.dy - cy;
    final lx = dx * cosR + dy * sinR;
    final ly = -dx * sinR + dy * cosR;
    // corners order: TR(0),TC(1),TL(2),LC(3),BL(4),BC(5),BR(6),RC(7).
    // Use corners[0] (TR) and corners[4] (BL) for full half extents.
    final hr = corners[0];
    final bl = corners[4];
    final hw = (hr.dx - bl.dx).abs() / 2;
    final hh = (hr.dy - bl.dy).abs() / 2;
    return lx >= -hw && lx <= hw && ly >= -hh && ly <= hh;
  }

  String? _hitTestImageSegment(Offset w, Figure fig) {
    for (var i = fig.segments.length - 1; i >= 0; i--) {
      final s = fig.segments[i];
      if (!s.isImage || s.imageData == null) continue;
      if (s.point1Index >= fig.points.length || s.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[s.point1Index];
      final p2 = fig.points[s.point2Index];
      final image = _imageFor(s.imageData);
      final size = _resolveImageSize(s, image);
      final mx = (p1.x + p2.x) / 2 + s.imageOffsetX;
      final my = (p1.y + p2.y) / 2 + s.imageOffsetY;
      final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
      final rotate = segAngle + s.imageRotate * math.pi / 180;
      final corners = _assetHandles(size.width / 2, size.height / 2, rotate, mx, my);
      if (_pointInRotatedRect(w, corners.take(8).toList(), mx, my, rotate)) {
        return s.id;
      }
    }
    return null;
  }

  /// In anchor mode, records the current image center/rotation of every image
  /// segment (optionally restricted to those attached to [ptIdx] when given)
  /// so that moving the rig points keeps the assets anchored in place (the
  /// offset compensates the point movement).
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
      if (s.point1Index >= fig.points.length ||
          s.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[s.point1Index];
      final p2 = fig.points[s.point2Index];
      final midX = (p1.x + p2.x) / 2 + s.imageOffsetX;
      final midY = (p1.y + p2.y) / 2 + s.imageOffsetY;
      final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
      _drag.anchorImgCenter[s.id] = Point2(midX, midY);
      _drag.anchorImgRot[s.id] = segAngle * 180 / math.pi + s.imageRotate;
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

    // A connected/cycle segment: the whole loop rotates as one rigid unit
    // around its top-most node ("A"). A normal segment (tree, no cycle) uses
    // plain pivot rotation: the grabbed point's branch rotates around the
    // joint toward the root.
    final isCycle = edgeCount >= comp.length;

    int centre;
    List<int> rotPts;
    if (isCycle) {
      // Top-most non-root node (e.g. "A" in root 0 -> A -> B/C/D -> A).
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
      // Clicking the pivot node itself behaves like any other point: normal
      // pivot rotation around a neighbour.
      centre = ptHit == pivotNode
          ? (seg != null
              ? (seg.point1Index == ptHit ? seg.point2Index : seg.point1Index)
              : (adj[ptHit]!.isNotEmpty ? adj[ptHit]!.first : ptHit))
          : pivotNode;
      rotPts = comp.where((i) => !allRoots.contains(i)).toList();
    } else {
      // Normal (tree) segment: rotate the grabbed point + its descendants
      // around the joint (parent toward the root).
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
      final seg = fig.getSegment(widget.controller.assetSegmentId ?? '');
      if (seg != null && seg.isImage) {
        if (d.assetOp == 'move') {
          seg.imageOffsetX = d.startOx + (w.dx - d.startX);
          seg.imageOffsetY = d.startOy + (w.dy - d.startY);
          widget.controller.forceUpdate();
        } else if (d.assetOp == 'rotate') {
          final cur = math.atan2(w.dy - d.assetCenterY, w.dx - d.assetCenterX);
          var delta = cur - d.startAngle;
          seg.imageRotate = d.startRot + delta * 180 / math.pi;
          widget.controller.forceUpdate();
        } else if (d.assetOp == 'resize') {
          _handleAssetResize(w, seg, d);
          widget.controller.forceUpdate();
        }
      }
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

  void _handleAssetResize(Offset w, Segment seg, _DragState d) {
    // Handle layout: 0=TR,1=TC,2=TL,3=LC,4=BL,5=BC,6=BR,7=RC
    // The image is drawn centered at midpoint+offset, so resizing only needs
    // to change imageWidth/imageHeight; the box grows/shrinks around center.
    final p1 = widget.controller.figure.points[seg.point1Index];
    final p2 = widget.controller.figure.points[seg.point2Index];
    final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final rotate = segAngle + seg.imageRotate * math.pi / 180;
    final cosR = math.cos(-rotate), sinR = math.sin(-rotate);
    final dx = w.dx - d.assetCenterX, dy = w.dy - d.assetCenterY;
    final lx = dx * cosR - dy * sinR;
    final ly = dx * sinR + dy * cosR;

    var newW = d.startW;
    var newH = d.startH;
    final h = d.assetHandle;
    if (h == 0 || h == 2 || h == 4 || h == 6) {
      newW = (lx.abs() * 2).clamp(10.0, double.infinity);
    }
    if (h == 1 || h == 3 || h == 5 || h == 7) {
      newH = (ly.abs() * 2).clamp(10.0, double.infinity);
    }
    seg.imageWidth = newW;
    seg.imageHeight = newH;
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

  void _handleTouchEnd() {
    final wasCreating = _drag.creating;
    final wasDragging = _drag.active || _drag.isPan;
    final wasAsset = _drag.assetDrag;
    _drag.reset();
    _lastPt = null;
    if (wasCreating) widget.controller.pushHistory();
    if (wasAsset) widget.controller.pushHistory();
    if (wasDragging) widget.controller.forceUpdate();
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

