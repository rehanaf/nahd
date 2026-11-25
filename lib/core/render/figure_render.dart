import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'opacity_groups.dart';
import '../models/figure.dart';
import '../models/figure_animation.dart';
import '../models/segment.dart';

/// Decodes a `data:image/...;base64,...` URI into a [ui.Image].
Future<ui.Image> decodeDataUriImage(String dataUri) async {
  final comma = dataUri.indexOf(',');
  final b64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
  final bytes = base64Decode(b64);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Collects every unique image URI referenced by image segments of [figure].
List<String> imageUrisOf(Figure figure) {
  final uris = <String>{};
  for (final seg in figure.segments) {
    if (!seg.isImage) continue;
    uris.addAll(seg.imageDataList);
  }
  return uris.toList();
}

/// A self-contained painter that draws a (already posed) figure, centred and
/// scaled to fit [Size] (contain). It reproduces the editor rendering
/// (cycle fills, line/circle/image/text segments, per-frame figure
/// visibility / opacity / colour override / sprite index) without any editor
/// overlays (points, connectors, handles…). Used by the fullscreen preview and
/// by the image/video exporters.
class FigureFramePainter extends CustomPainter {
  /// The figure to draw; points must already be posed at [time].
  final Figure figure;

  /// Timeline position in FRAME indices (used for visibility / opacity /
  /// colour / sprite keyframes).
  final double time;

  /// When true, per-frame figure overrides and sprite keyframes are applied.
  final bool animate;

  final ui.Image? Function(String? dataUri) imageFor;

  FigureFramePainter({
    required this.figure,
    required this.time,
    this.animate = true,
    required this.imageFor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = figure.canvasWidth;
    final h = figure.canvasHeight;
    if (w <= 0 || h <= 0) return;
    final scale = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate((size.width - w * scale) / 2, (size.height - h * scale) / 2);
    canvas.scale(scale);

    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()..color = parseHexColor(figure.canvasColor) ?? const Color(0xFFFFFFFF),
    );

    // Fills and segments with the same opacity are painted into one layer so
    // overlapping parts do not stack their alpha (same logic as onion skin).
    final opacityGroups = OpacityPaintGroups();
    _paintCycleFills(canvas, opacityGroups);
    _paintSegments(canvas, opacityGroups);
    opacityGroups.paint(canvas);

    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Segments
  // -------------------------------------------------------------------------

  void _paintSegments(Canvas canvas, OpacityPaintGroups groups) {
    final sorted = figure.segmentsInDrawOrder(animate ? time : null);
    for (final seg in sorted) {
      final style = figure.styleFor(seg, time, enabled: animate);
      if (style.hidden || seg.isNone) continue;
      if (animate && !_visibleAtSeg(seg)) continue;
      if (seg.point1Index >= figure.points.length ||
          seg.point2Index >= figure.points.length) {
        continue;
      }
      final p1 = figure.points[seg.point1Index];
      final p2 = figure.points[seg.point2Index];
      final opacity = _opacityAtSeg(seg);
      final overColor = _colorOverrideAtSeg(seg);

      groups.add(opacity, () {
        // Everything inside an opacity layer is opaque. The bucket's layer
        // applies the alpha once when it is composited back onto the canvas.
        switch (seg.type) {
          case 'line':
            final baseColor = parseHexColor(overColor ?? style.color) ??
                const Color(0xFFD1D5DB);
            final paint = Paint()
              ..color = baseColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.width <= 0 ? 3 : style.width
              ..strokeCap = _capFor(style.lineCap);
            _drawSegmentLine(canvas, paint, seg, p1, p2, style);
          case 'circle':
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
              math.sqrt((p2.x - p1.x) * (p2.x - p1.x) +
                      (p2.y - p1.y) * (p2.y - p1.y)) /
                  2,
              1.0,
            );
            if (style.filled) {
              final baseColor = parseHexColor(overColor) ??
                  parseHexColor(style.fillColor) ??
                  parseHexColor(style.color) ??
                  const Color(0xFFD1D5DB);
              canvas.drawCircle(
                Offset(mx, my),
                r,
                Paint()..color = baseColor,
              );
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
          case 'image':
            _paintImageSegment(canvas, seg, p1, p2, 1.0, style);
          case 'text':
            _paintTextSegment(canvas, seg, style, p1, p2, 1.0, overColor);
        }
      });
    }
  }

  void _paintImageSegment(Canvas canvas, Segment seg, Point2 p1, Point2 p2,
      double opacity, SegmentFrameStyle style) {
    int imageIndex = seg.activeImageIndex;
    if (animate) {
      imageIndex =
          figure.getSegmentImageIndex(seg.id, time) ?? imageIndex;
    }
    String? data = seg.imageDataList.isNotEmpty &&
            imageIndex >= 0 &&
            imageIndex < seg.imageDataList.length
        ? seg.imageDataList[imageIndex]
        : null;
    final image = imageFor(data);
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
      Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.restore();
  }

  void _paintTextSegment(Canvas canvas, Segment seg, SegmentFrameStyle style,
      Point2 p1, Point2 p2, double opacity, String? overColor) {
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

  Size _resolveImageSize(SegmentFrameStyle style, ui.Image image) {
    var w = style.imageWidth is num ? (style.imageWidth as num).toDouble() : 100.0;
    var h = style.imageHeight is num ? (style.imageHeight as num).toDouble() : 100.0;
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

  void _drawSegmentLine(Canvas canvas, Paint paint, Segment seg, Point2 p1,
      Point2 p2, SegmentFrameStyle style) {
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
  // Cycle fills (adapted 1:1 from the editor painter)
  // -------------------------------------------------------------------------

  void _paintCycleFills(Canvas canvas, OpacityPaintGroups groups) {
    final fig = figure;
    if (fig.segments.isEmpty) return;
    final adj = <int, List<int>>{};
    for (var i = 0; i < fig.points.length; i++) {
      adj[i] = [];
    }
    for (final s in fig.segments) {
      if (fig.styleFor(s, time, enabled: animate).hidden || s.isNone) continue;
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
      if (animate && !_visibleAt(compPts.first)) continue;

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
          final filled = figure.frameBool('cycle:$key:filled', time, entry.filled);
          if (filled) {
            final fillColor = _cycleFillColor(key, ordered.first, entry);
            final path = _cyclePath(pts);
            groups.add(_opacityAtPoint(ordered.first), () {
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
                final filled =
                    figure.frameBool('cycle:$key:filled', time, entry.filled);
                if (filled) {
                  final fillColor = _cycleFillColor(key, seed, entry);
                  final path = _cyclePath([...cur.path, seed]);
                  groups.add(_opacityAtPoint(seed), () {
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

  Color _cycleFillColor(String key, int point, CycleFill entry) {
    final overColor = animate
        ? figure.getFigureColorOverride(figure.figureKeyFor(point), time)
        : null;
    final cycleColor = animate
        ? figure.frameNullableString(
            'cycle:$key:fillColor', time, entry.fillColor)
        : entry.fillColor;
    return parseHexColor(overColor) ??
        parseHexColor(cycleColor) ??
        const Color(0xFFD1D5DB);
  }

  Path _cyclePath(List<int> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(figure.points[pts[0]].x, figure.points[pts[0]].y);
    for (var j = 0; j < pts.length; j++) {
      final next = (j + 1) % pts.length;
      final seg = _segmentBetween(pts[j], pts[next]);
      final style = seg == null
          ? null
          : figure.styleFor(seg, time, enabled: animate);
      if (style != null &&
          style.curved &&
          style.controlDX != null &&
          style.controlDY != null) {
        final mx = (figure.points[pts[j]].x + figure.points[pts[next]].x) / 2;
        final my = (figure.points[pts[j]].y + figure.points[pts[next]].y) / 2;
        path.quadraticBezierTo(
          mx + style.controlDX!,
          my + style.controlDY!,
          figure.points[pts[next]].x,
          figure.points[pts[next]].y,
        );
      } else {
        path.lineTo(figure.points[pts[next]].x, figure.points[pts[next]].y);
      }
    }
    path.close();
    return path;
  }

  Segment? _segmentBetween(int a, int b) {
    for (final s in figure.segments) {
      if ((s.point1Index == a && s.point2Index == b) ||
          (s.point1Index == b && s.point2Index == a)) {
        return s;
      }
    }
    return null;
  }

  bool _visibleAt(int pointIdx) {
    if (pointIdx < 0 || pointIdx >= figure.points.length) return true;
    return figure.getFigureVisibility(figure.figureKeyFor(pointIdx), time);
  }

  bool _visibleAtSeg(Segment seg) {
    final k = figure.segmentFigureKey(seg);
    if (k < 0) return true;
    return figure.getFigureVisibility(k, time);
  }

  double _opacityAtSeg(Segment seg) {
    final k = figure.segmentFigureKey(seg);
    if (k < 0) return 1.0;
    return figure.getFigureOpacity(k, time);
  }

  double _opacityAtPoint(int point) {
    if (!animate) return 1.0;
    final k = figure.figureKeyFor(point);
    if (k < 0) return 1.0;
    return figure.getFigureOpacity(k, time);
  }

  String? _colorOverrideAtSeg(Segment seg) {
    if (!animate) return null;
    final k = figure.segmentFigureKey(seg);
    if (k < 0) return null;
    return figure.getFigureColorOverride(k, time);
  }

  @override
  bool shouldRepaint(covariant FigureFramePainter oldDelegate) =>
      oldDelegate.figure != figure ||
      oldDelegate.time != time ||
      oldDelegate.animate != animate;
}

// ===========================================================================
// Exporters
// ===========================================================================

/// Renders the figure / animation into static images, GIF and PNG sequences.
class FigureExport {
  final Figure figure;
  final FigureAnimation? animation;
  final bool autoEasing;
  final Map<String, ui.Image> _images = {};

  FigureExport(
    this.figure, {
    this.animation,
    this.autoEasing = true,
  });

  /// Number of frames in the exported animation (>= 1).
  int get totalFrames {
    final d = animation?.duration ?? 0;
    return math.max(1, d.round().clamp(1, 1000000));
  }

  Future<void> preload() async {
    for (final uri in imageUrisOf(figure)) {
      if (_images.containsKey(uri)) continue;
      try {
        _images[uri] = await decodeDataUriImage(uri);
      } catch (_) {}
    }
  }

  ui.Image? _imageFor(String? uri) =>
      uri == null ? null : _images[uri];

  /// Renders the figure posed at [time] (frame units) to a [ui.Image] of
  /// `canvasSize * scale` pixels.
  Future<ui.Image> renderFrame(double time, double scale) async {
    final posed = figure.clone();
    if (animation != null) animation!.applyToFigure(posed, time, autoEasing);
    final w = math.max(1, (posed.canvasWidth * scale).round());
    final h = math.max(1, (posed.canvasHeight * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    FigureFramePainter(
      figure: posed,
      time: time,
      animate: animation != null,
      imageFor: _imageFor,
    ).paint(canvas, Size(w.toDouble(), h.toDouble()));
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  /// Renders one frame as PNG bytes.
  Future<Uint8List> renderFramePng(double time, double scale) async {
    final image = await renderFrame(time, scale);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List() ?? Uint8List(0);
    } finally {
      image.dispose();
    }
  }

  /// Renders the whole animation as a looping GIF.
  Future<Uint8List> renderGif({
    required double fps,
    double scale = 1,
    bool loop = true,
  }) async {
    await preload();
    final total = totalFrames;
    final delayMs = fps > 0 ? (100 / fps).round() : 8;
    final gif = img.GifEncoder(delay: delayMs.clamp(1, 65535), repeat: loop ? 0 : -1);
    for (var i = 0; i < total; i++) {
      final frame = await _renderRgba(i.toDouble(), scale);
      gif.addFrame(frame);
    }
    return gif.finish() ?? Uint8List(0);
  }

  /// Renders every frame as a PNG and bundles them in a zip archive.
  Future<Uint8List> renderPngZip({double scale = 1}) async {
    await preload();
    final total = totalFrames;
    final archive = Archive();
    for (var i = 0; i < total; i++) {
      final png = await renderFramePng(i.toDouble(), scale);
      archive.addFile(ArchiveFile(
        'frame_${(i + 1).toString().padLeft(4, '0')}.png',
        png.length,
        png,
      ));
    }
    final zipped = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipped);
  }

  Future<img.Image> _renderRgba(double time, double scale) async {
    final image = await renderFrame(time, scale);
    try {
      final w = image.width;
      final h = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return img.Image(width: w, height: h);
      }
      return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: data.buffer,
        numChannels: 4,
      );
    } finally {
      image.dispose();
    }
  }
}

// ===========================================================================
// Fullscreen preview
// ===========================================================================

/// A mouse/touch-free animated preview of the whole canvas (playback of the
/// project's animation at its FPS), roaming above the editor UI.
class FigurePreviewScreen extends StatefulWidget {
  final Figure figure;
  final FigureAnimation? animation;
  final double fps;
  final double initialTime;

  const FigurePreviewScreen({
    super.key,
    required this.figure,
    required this.animation,
    required this.fps,
    this.initialTime = 0,
  });

  @override
  State<FigurePreviewScreen> createState() => _FigurePreviewScreenState();
}

class _FigurePreviewScreenState extends State<FigurePreviewScreen> {
  late double _t;
  final Map<String, ui.Image> _images = {};
  late final FigureExport _export;
  Timer? _timer;
  bool _playing = true;

  double get _duration =>
      widget.animation?.duration ?? (widget.figure.animations.isNotEmpty ? 1 : 1);

  @override
  void initState() {
    super.initState();
    _t = widget.initialTime.clamp(0.0, math.max(0, _duration));
    _export = FigureExport(widget.figure, animation: widget.animation);
    _preload();
    _start();
  }

  Future<void> _preload() async {
    await _export.preload();
    if (mounted) setState(() {});
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_playing) return;
      final dur = _duration;
      if (dur <= 0) return;
      var next = _t + widget.fps * 0.033;
      if (next >= dur) {
        next = next % dur;
      }
      setState(() => _t = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final im in _images.values) {
      im.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _duration;
    final frameCount = math.max(1, duration.round());
    final frame = _t.round().clamp(0, frameCount - 1);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    '${frame + 1} / $frameCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _playing ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () {
                      setState(() => _playing = !_playing);
                      if (_playing) _start();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final aspect = (widget.figure.canvasHeight <= 0)
                        ? 16 / 9
                        : widget.figure.canvasWidth / widget.figure.canvasHeight;
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size(constraints.maxWidth,
                              constraints.maxWidth / aspect),
                          painter: FigureFramePainter(
                            figure: _posed(),
                            time: _t,
                            animate: widget.animation != null,
                            imageFor: _export._imageFor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Figure _posed() {
    final fig = widget.figure.clone();
    widget.animation?.applyToFigure(fig, _t, true);
    return fig;
  }
}