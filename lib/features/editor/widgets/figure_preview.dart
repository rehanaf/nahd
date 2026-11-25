import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/render/opacity_groups.dart';
import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';

Color? _parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
  if (h.length == 8) {
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
  return null;
}

/// Renders a [Figure] scaled to cover a box, centered (crop overflow),
/// matching the 1280x720 (16:9) canvas convention of the editor.
///
/// When [enableFrameOverrides] is true, the painter resolves every property
/// through [Figure.styleFor] at [time], so thumbnails match the editor canvas
/// (including per-frame hidden/curve/style changes). Static project tiles keep
/// the default `false` so they always show the newest, clean asset state.
class FigurePreview extends StatefulWidget {
  final Figure? figure;
  final double? time;
  final bool enableFrameOverrides;

  const FigurePreview({
    super.key,
    this.figure,
    this.time,
    this.enableFrameOverrides = false,
  });

  @override
  State<FigurePreview> createState() => _FigurePreviewState();
}

class _FigurePreviewState extends State<FigurePreview> {
  final Map<String, ui.Image> _images = {};

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(covariant FigurePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figure != widget.figure) _loadImages();
  }

  static Uint8List? _decode(String uri) {
    final comma = uri.indexOf(',');
    final b64 = comma >= 0 ? uri.substring(comma + 1) : uri;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadImages() async {
    final fig = widget.figure;
    if (fig == null) return;
    for (final seg in fig.segments) {
      if (!seg.isImage) continue;
      for (final data in seg.imageDataList) {
        if (data.isEmpty || _images.containsKey(data)) continue;
        final bytes = _decode(data);
        if (bytes == null) continue;
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          if (mounted) setState(() => _images[data] = frame.image);
        } catch (_) {}
      }
    }
  }

  ui.Image? _imageFor(String? uri) => uri == null ? null : _images[uri];

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: FigurePreviewPainter(
        widget.figure,
        time: widget.time,
        enableFrameOverrides: widget.enableFrameOverrides,
        imageFor: _imageFor,
      ),
    );
  }
}

class FigurePreviewPainter extends CustomPainter {
  final Figure? figure;
  final double? time;
  final bool enableFrameOverrides;
  final ui.Image? Function(String?) imageFor;

  FigurePreviewPainter(
    this.figure, {
    this.time,
    this.enableFrameOverrides = false,
    this.imageFor = _nullImageFor,
  });

  static ui.Image? _nullImageFor(String? uri) => null;

  Figure get fig => figure!;

  double get _time => time ?? 0;

  SegmentFrameStyle _style(Figure fig, Segment seg) =>
      fig.styleFor(seg, _time, enabled: enableFrameOverrides);

  double _opacityAt(Figure fig, int point) {
    if (!enableFrameOverrides) return 1;
    final key = fig.figureKeyFor(point);
    if (key < 0) return 1;
    return fig.getFigureOpacity(key, _time);
  }

  /// Honour per-figure visibility keyframes so frame thumbnails/previews
  /// match the canvas: a figure deleted at frame N must still show in N-1.
  bool _figureVisible(Figure fig, Segment seg) {
    if (!enableFrameOverrides) return true;
    final key = fig.segmentFigureKey(seg);
    return fig.getFigureVisibility(key, _time);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fig = figure;
    final canvasColor = fig != null
        ? (_parseHex(fig.canvasColor) ?? const Color(0xFFFFFFFF))
        : const Color(0xFFFFFFFF);
    if (fig == null || fig.points.isEmpty || fig.segments.isEmpty) {
      canvas.drawRect(Offset.zero & size, Paint()..color = canvasColor);
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasColor);

    final figW = fig.canvasWidth;
    final figH = fig.canvasHeight;
    final scale = math.max(size.width / figW, size.height / figH);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);

    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: figW, height: figH),
      Paint()..color = canvasColor,
    );

    final sorted = fig.segmentsInDrawOrder(enableFrameOverrides ? _time : null);
    final opacityGroups = OpacityPaintGroups();
    _paintPreviewFills(canvas, fig, opacityGroups);
    _paintPreviewImages(canvas);
    for (final seg in sorted) {
      final style = _style(fig, seg);
      if (style.hidden || seg.type == 'image' || seg.isNone) continue;
      if (!_figureVisible(fig, seg)) continue;
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];

      // Figure-wide colour override applies on top of the segment's own
      // colour, using the same per-figure scoping as the editor.
      final overColor = fig.getFigureColorOverride(
        fig.segmentFigureKey(seg),
        _time,
      );
      final baseColor =
          _parseHex(overColor ?? style.color) ?? const Color(0xFFD1D5DB);
      final opacity = _opacityAt(fig, seg.point1Index);

      opacityGroups.add(opacity, () {
        if (seg.type == 'text') {
          final text = style.text;
          if (text != null && text.isNotEmpty) {
            final tp = TextPainter(
              text: TextSpan(
                text: text,
                style: TextStyle(
                  color: baseColor,
                  fontSize: style.textSize <= 0 ? 32 : style.textSize,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Onest',
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            canvas.save();
            canvas.translate((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
            canvas.rotate(math.atan2(p2.y - p1.y, p2.x - p1.x));
            tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
            canvas.restore();
          }
          return;
        }

        if (seg.type == 'circle') {
          var mx = (p1.x + p2.x) / 2;
          var my = (p1.y + p2.y) / 2;
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
            canvas.drawCircle(
              Offset(mx, my),
              r,
              Paint()
                ..color =
                    _parseHex(overColor) ??
                    _parseHex(style.fillColor) ??
                    _parseHex(style.color) ??
                    const Color(0xFFD1D5DB),
            );
          }
          canvas.drawCircle(
            Offset(mx, my),
            r,
            Paint()
              ..color = baseColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.width <= 0 ? 3 : style.width,
          );
          return;
        }

        final paint = Paint()
          ..color = baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.width <= 0 ? 3 : style.width;
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
      });
    }
    opacityGroups.paint(canvas);

    canvas.restore();
  }

  /// Recreates the editor's cycle-fill computation (per-connected-component
  /// loop detection) so filled regions appear in the preview with their figure
  /// colour override applied at the requested frame.
  void _paintPreviewFills(
    Canvas canvas,
    Figure fig,
    OpacityPaintGroups groups,
  ) {
    if (fig.segments.isEmpty) return;
    final adj = <int, List<int>>{};
    for (var i = 0; i < fig.points.length; i++) {
      adj[i] = [];
    }
    for (final s in fig.segments) {
      if (_style(fig, s).hidden || s.isNone) continue;
      if (!_figureVisible(fig, s)) continue;
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

    Color? fillColorFor(String? stored, String? cycleKey, int point) {
      final overColor = fig.getFigureColorOverride(
        fig.figureKeyFor(point),
        _time,
      );
      final cycleColor = cycleKey == null
          ? stored
          : enableFrameOverrides
          ? fig.frameNullableString('cycle:$cycleKey:fillColor', _time, stored)
          : stored;
      return _parseHex(overColor) ??
          _parseHex(cycleColor) ??
          const Color(0xFFD1D5DB);
    }

    bool cycleFilled(String key, CycleFill entry) => enableFrameOverrides
        ? fig.frameBool('cycle:$key:filled', _time, entry.filled)
        : entry.filled;

    void drawCycle(
      List<int> pts,
      String? storedColor,
      String? cycleKey,
      int point,
    ) {
      if (pts.length < 3) return;
      final path = _previewCyclePath(fig, pts, cycleKey: cycleKey);
      groups.add(_opacityAt(fig, point), () {
        canvas.drawPath(
          path,
          Paint()..color = fillColorFor(storedColor, cycleKey, point)!,
        );
      });
    }

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
          final sortedPts = [...pts]..sort();
          final key = sortedPts.join(',');
          final entry = cf[key];
          drawCycle(pts, entry?.fillColor, key, pts.first);
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
                final entry = cf[key];
                if (entry == null || cycleFilled(key, entry)) {
                  drawCycle([...cur.path, seed], entry?.fillColor, key, seed);
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

  Path _previewCyclePath(Figure fig, List<int> pts, {String? cycleKey}) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(fig.points[pts[0]].x, fig.points[pts[0]].y);
    for (var j = 0; j < pts.length; j++) {
      final next = (j + 1) % pts.length;
      final seg = _previewSegmentBetween(fig, pts[j], pts[next]);
      final style = seg == null ? null : _style(fig, seg);
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

  Segment? _previewSegmentBetween(Figure fig, int a, int b) {
    for (final s in fig.segments) {
      if ((s.point1Index == a && s.point2Index == b) ||
          (s.point1Index == b && s.point2Index == a)) {
        return s;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant FigurePreviewPainter oldDelegate) => true;

  /// Draws image segments (the asset-bearing parts) in the preview.
  void _paintPreviewImages(Canvas canvas) {
    for (final seg in fig.segments) {
      if (seg.type != 'image' || seg.isNone) continue;
      if (!_figureVisible(fig, seg)) continue;
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final style = _style(fig, seg);
      if (style.hidden) continue;
      final imageIndex = enableFrameOverrides
          ? (fig.getSegmentImageIndex(seg.id, _time) ?? seg.activeImageIndex)
          : seg.activeImageIndex;
      final data =
          seg.imageDataList.isNotEmpty &&
              imageIndex >= 0 &&
              imageIndex < seg.imageDataList.length
          ? seg.imageDataList[imageIndex]
          : null;
      final image = imageFor(data);
      if (image == null) continue;

      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];
      final mx = (p1.x + p2.x) / 2;
      final my = (p1.y + p2.y) / 2;
      final segAngle = math.atan2(p2.y - p1.y, p2.x - p1.x);
      final rotate = segAngle + style.imageRotate * math.pi / 180;
      final size = _previewImageSize(style, image);
      canvas.save();
      canvas.translate(mx, my);
      canvas.rotate(rotate);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width,
          height: size.height,
        ),
        Paint(),
      );
      canvas.restore();
    }
  }

  Size _previewImageSize(SegmentFrameStyle style, ui.Image image) {
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
}

/// Parses a project's figure JSON into a [Figure], or null if unavailable.
Figure? figureFromProjectData(String? figureJson) {
  if (figureJson == null || figureJson.isEmpty) return null;
  try {
    return Figure.fromJsonString(figureJson);
  } catch (_) {
    return null;
  }
}
