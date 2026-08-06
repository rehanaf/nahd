import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/figure.dart';

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
    for (final seg in sorted) {
      if (seg.hidden || seg.type == 'image' || seg.isNone) continue;
      if (seg.point1Index >= fig.points.length ||
          seg.point2Index >= fig.points.length) {
        continue;
      }
      final p1 = fig.points[seg.point1Index];
      final p2 = fig.points[seg.point2Index];

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
              ..color = _parseHex(seg.fillColor) ??
                  _parseHex(seg.color) ??
                  const Color(0xFFD1D5DB),
          );
        }
        canvas.drawCircle(
          Offset(mx, my),
          r,
          Paint()
            ..color = _parseHex(seg.color) ?? const Color(0xFFD1D5DB)
            ..style = PaintingStyle.stroke
            ..strokeWidth = seg.width <= 0 ? 3 : seg.width,
        );
        continue;
      }

      final paint = Paint()
        ..color = _parseHex(seg.color) ?? const Color(0xFFD1D5DB)
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
