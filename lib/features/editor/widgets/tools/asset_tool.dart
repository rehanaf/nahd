part of '../figure_canvas.dart';

extension _AssetTool on _FigureCanvasState {
  void handleAssetStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.asset || widget.controller.isAssetMode) {
      if (_handleAssetStart(w, fig)) return;
    }
  }

  void handleAssetMove(Offset w, Figure fig, _DragState d) {
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
    }
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
      const hitR = 12.0 / 1.0; // in world units
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
    return false;
  }

  bool _pointInRotatedRect(
      Offset w, List<Offset> corners, double cx, double cy, double rotate) {
    if (corners.length < 4) return false;
    final cosR = math.cos(rotate), sinR = math.sin(rotate);
    final dx = w.dx - cx, dy = w.dy - cy;
    final lx = dx * cosR + dy * sinR;
    final ly = -dx * sinR + dy * cosR;
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

  void _handleAssetResize(Offset w, Segment seg, _DragState d) {
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
}
