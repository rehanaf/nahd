import 'dart:math' as math;

import 'package:flutter/material.dart';

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
class FigurePreview extends StatelessWidget {
  final Figure? figure;

  const FigurePreview({super.key, this.figure});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: FigurePreviewPainter(figure),
    );
  }
}

class FigurePreviewPainter extends CustomPainter {
  final Figure? figure;

  FigurePreviewPainter(this.figure);

  static const Color bgOuter = Color(0xFF111319);

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
    canvas.drawRect(Offset.zero & size, Paint()..color = bgOuter);

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

    final sorted = fig.segmentsInDrawOrder();
    _paintPreviewFills(canvas, fig);
    for (final seg in sorted) {
      if (seg.hidden || seg.type == 'image' || seg.isNone) continue;
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];

      // Figure-wide colour override (default keyframe) applies on top of the
      // segment's own colour, using the same per-figure scoping as the editor.
      final overColor = fig.getFigureColorOverride(fig.segmentFigureKey(seg), 0);
      final baseColor = _parseHex(overColor ?? seg.color) ?? const Color(0xFFD1D5DB);

      if (seg.type == 'text') {
        final text = seg.text;
        if (text != null && text.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: baseColor,
                fontSize: seg.textSize <= 0 ? 32 : seg.textSize,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
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
        continue;
      }

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
          canvas.drawCircle(
            Offset(mx, my),
            r,
            Paint()
              ..color = _parseHex(overColor) ??
                  _parseHex(seg.fillColor) ??
                  _parseHex(seg.color) ??
                  const Color(0xFFD1D5DB),
          );
        }
        canvas.drawCircle(
          Offset(mx, my),
          r,
          Paint()
            ..color = baseColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = seg.width <= 0 ? 3 : seg.width,
        );
        continue;
      }

      final paint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = seg.width <= 0 ? 3 : seg.width;
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

    canvas.restore();
  }

  /// Recreates the editor's cycle-fill computation (per-connected-component
  /// loop detection) so filled regions appear in the preview with their figure
  /// colour override applied at the default keyframe.
  void _paintPreviewFills(Canvas canvas, Figure fig) {
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

    Color? fillColorFor(String? stored, int point) {
      final overColor = fig.getFigureColorOverride(fig.figureKeyFor(point), 0);
      return _parseHex(overColor) ?? _parseHex(stored) ?? const Color(0xFFD1D5DB);
    }

    void drawCycle(List<int> pts, String? storedColor, int point) {
      if (pts.length < 3) return;
      final path = _previewCyclePath(fig, pts);
      canvas.drawPath(
        path,
        Paint()..color = fillColorFor(storedColor, point)!,
      );
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
          final stored = cf[sortedPts.join(',')];
          drawCycle(pts, stored?.fillColor, pts.first);
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
                final entry = cf[key];
                if (entry == null || entry.filled) {
                  drawCycle(
                    [...cur.path, seed],
                    entry?.fillColor,
                    seed,
                  );
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

  Path _previewCyclePath(Figure fig, List<int> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(fig.points[pts[0]].x, fig.points[pts[0]].y);
    for (var j = 0; j < pts.length; j++) {
      final next = (j + 1) % pts.length;
      final seg = _previewSegmentBetween(fig, pts[j], pts[next]);
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
  bool shouldRepaint(covariant FigurePreviewPainter oldDelegate) =>
      oldDelegate.figure != figure;
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
