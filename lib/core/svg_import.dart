import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:xml/xml.dart';

import 'models/figure.dart';
import 'models/segment.dart';

/// One body part (a `<g>`/layer) of an imported SVG, holding the flattened
/// outlines of every shape that belongs to it.
class SvgLayer {
  final String name;
  final List<List<Point2>> shapes;
  final List<bool> closed;

  /// Per-shape resolved fill color (hex) or null when `fill="none"`/absent.
  final List<String?> fills;

  /// Per-shape resolved stroke color (hex) or null when `stroke="none"`/absent.
  final List<String?> strokes;

  /// Per-shape stroke width in SVG units (null = SVG default).
  final List<double?> strokeWidths;

  const SvgLayer({
    required this.name,
    required this.shapes,
    required this.closed,
    required this.fills,
    required this.strokes,
    required this.strokeWidths,
  });
}

/// Flatten an SVG string into a [Figure] made of per-layer vector segments.
///
/// * Each `<g>` (or root-level shape) becomes one layer.
/// * Each shape's outline is sampled into points (via PathMetrics) and
///   connected with `line` segments; closed shapes get a closing segment.
/// * Each layer becomes its own root in [Figure.rootIndices] (sub-figure).
/// * Fill/stroke colors are copied onto the layer's segments when present.
///
/// Coordinates are rescaled from the SVG viewBox so the result fits inside
/// [canvasWidth] x [canvasHeight] with a margin.
Figure parseSvgFigure(
  String svgText, {
  double canvasWidth = 1280,
  double canvasHeight = 720,
}) {
  final layers = _parseLayers(svgText);
  return _buildFigure(
    layers,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );
}

/// Where a set of outline points maps onto the canvas (world space).
class _FitInfo {
  final double scale, offsetX, offsetY;
  const _FitInfo(this.scale, this.offsetX, this.offsetY);

  Point2 map(Point2 p) => Point2(p.x * scale + offsetX, p.y * scale + offsetY);
}

_FitInfo _fitToCanvas(
  List<Point2> all, {
  required double canvasWidth,
  required double canvasHeight,
}) {
  var minX = all.first.x, minY = all.first.y;
  var maxX = all.first.x, maxY = all.first.y;
  for (final p in all) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  final bw = math.max(maxX - minX, 1);
  final bh = math.max(maxY - minY, 1);
  final margin = 40.0;
  final availW = math.max(canvasWidth - margin * 2, 1);
  final availH = math.max(canvasHeight - margin * 2, 1);
  final scale = math.min(availW / bw, availH / bh);
  final offX = (canvasWidth - bw * scale) / 2 - minX * scale;
  final offY = (canvasHeight - bh * scale) / 2 - minY * scale;
  return _FitInfo(scale, offX, offY);
}

/// A per-layer bounding box in SVG source coordinates.
class _LayerBox {
  final double minX, minY, maxX, maxY;
  const _LayerBox(this.minX, this.minY, this.maxX, this.maxY);
  double get width => math.max(maxX - minX, 1);
  double get height => math.max(maxY - minY, 1);
}

_LayerBox _layerBox(SvgLayer layer) {
  var lx = double.infinity, ly = double.infinity;
  var mx = double.negativeInfinity, my = double.negativeInfinity;
  for (final shape in layer.shapes) {
    for (final p in shape) {
      if (p.x < lx) lx = p.x;
      if (p.y < ly) ly = p.y;
      if (p.x > mx) mx = p.x;
      if (p.y > my) my = p.y;
    }
  }
  return _LayerBox(lx, ly, mx, my);
}

/// Import the SVG as a set of raster assets: each `<g>`/layer becomes a
/// single `image` segment (a PNG rendered from that layer), so each body part
/// is one independent, rigid image exactly like an image asset.
///
/// Renders each layer with `dart:ui` at an offscreen resolution, encodes it as
/// base64 PNG, and positions it on the canvas via an `image` segment spanning
/// the layer's bounds. Each layer still becomes its own root (sub-figure).
Future<Figure> parseSvgFigureAsAssets(
  String svgText, {
  double canvasWidth = 1280,
  double canvasHeight = 720,
  double renderScale = 2.0,
}) async {
  final layers = _parseLayers(svgText);
  final all = <Point2>[];
  for (final layer in layers) {
    for (final shape in layer.shapes) {
      all.addAll(shape);
    }
  }
  if (all.isEmpty) {
    final empty = Figure();
    empty.points.clear();
    empty.rootIndices.clear();
    return empty;
  }

  final fit = _fitToCanvas(
    all,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );

  final figure = Figure();
  figure.points.clear();
  final roots = <int>[];

  for (final layer in layers) {
    final box = _layerBox(layer);
    // Render this layer to a PNG.
    final png = await _renderLayerPng(layer, box, renderScale: renderScale);
    if (png == null) continue;

    // The image segment is anchored by two points: the left and right edge of
    // the layer's mapped bounds, so the rect stays at the same spot/size.
    final tl = fit.map(Point2(box.minX, box.minY));
    final br = fit.map(Point2(box.maxX, box.maxY));
    final width = br.x - tl.x;
    final height = br.y - tl.y;
    if (width < 1 || height < 1) continue;

    final startIdx = figure.points.length;
    figure.points.add(tl);
    figure.points.add(Point2(br.x, tl.y));

    final seg = Segment('image')
      ..point1Index = startIdx
      ..point2Index = startIdx + 1
      ..imageData = 'data:image/png;base64,${base64Encode(png)}'
      ..imageWidth = width
      ..imageHeight = height
      ..imageOffsetX = 0.0
      ..imageOffsetY = height / 2
      ..layer = figure.segments.length;
    figure.segments.add(seg);

    if (!roots.contains(startIdx)) roots.add(startIdx);
  }

  figure.rootIndices..clear()..addAll(roots);
  figure.ensureSegmentsInDefaultGroup();
  return figure;
}

// ---------------------------------------------------------------------------
// XML / layer extraction
// ---------------------------------------------------------------------------

class _Accum {
  final List<List<Point2>> shapes = [];
  final List<bool> closed = [];
  final List<String?> fills = [];
  final List<String?> strokes = [];
  final List<double?> strokeWidths = [];
}

List<SvgLayer> _parseLayers(String svgText) {
  final doc = XmlDocument.parse(svgText);
  final root = _svgRoot(doc.rootElement);
  if (root == null) return [];

  final gradients = _collectGradients(doc);

  // SVG presentation attributes (fill/stroke) inherit onto children, so the
  // root <svg> attributes seed the inherited values.
  final rootFill = _attr(root, 'fill');
  final rootStroke = _attr(root, 'stroke');

  final byName = <String, _Accum>{};
  final order = <String>[];
  final counter = <int>[0];

  _Accum ensure(String name) =>
      byName.putIfAbsent(name, () { order.add(name); return _Accum(); });

  String autoName() {
    counter[0]++;
    return 'Layer ${counter[0]}';
  }

  void rec(XmlElement el, _M t, String? layerName,
      String? inheritedFill, String? inheritedStroke) {
    final elT = t.compose(_parseTransform(el));
    for (final child in el.childElements) {
      final tag = child.name.local.toLowerCase();
      if (tag == 'g' || tag == 'a') {
        final name = _layerName(child) ?? layerName ?? autoName();
        rec(
          child,
          elT,
          name,
          _attr(child, 'fill') ?? inheritedFill,
          _attr(child, 'stroke') ?? inheritedStroke,
        );
      } else if (_isShape(tag)) {
        final name = layerName ?? autoName();
        final pts = _shapeOutline(child, elT);
        if (pts == null || pts.length < 2) continue;
        final acc = ensure(name);
        acc.shapes.add(pts);
        acc.closed.add(_shapeClosed(tag));
        acc.fills.add(_resolveColor(_attr(child, 'fill') ?? inheritedFill, gradients));
        acc.strokes.add(_resolveColor(_attr(child, 'stroke') ?? inheritedStroke, gradients));
        acc.strokeWidths.add(_attrNum(child, 'stroke-width'));
      } else if (tag == 'svg' || tag == 'switch') {
        rec(child, elT, layerName, inheritedFill, inheritedStroke);
      }
    }
  }

  rec(root, _M.identity(), null, rootFill, rootStroke);

  final result = <SvgLayer>[];
  for (final name in order) {
    final acc = byName[name]!;
    if (acc.shapes.isEmpty) continue;
    result.add(SvgLayer(
      name: name,
      shapes: acc.shapes,
      closed: acc.closed,
      fills: acc.fills,
      strokes: acc.strokes,
      strokeWidths: acc.strokeWidths,
    ));
  }
  return result;
}

XmlElement? _svgRoot(XmlElement root) {
  var el = root;
  while (el.name.local.toLowerCase() != 'svg' && el.childElements.isNotEmpty) {
    el = el.childElements.first;
  }
  return el.name.local.toLowerCase() == 'svg' ? el : null;
}

bool _isShape(String tag) =>
    tag == 'path' || tag == 'circle' || tag == 'rect' || tag == 'ellipse' ||
    tag == 'polygon' || tag == 'polyline' || tag == 'line';

bool _shapeClosed(String tag) =>
    tag == 'circle' || tag == 'ellipse' || tag == 'rect' || tag == 'polygon' ||
    tag == 'path';

String? _layerName(XmlElement el) {
  for (final attr in ['id', 'data-name', 'data-label', 'inkscape:label']) {
    final v = el.getAttribute(attr);
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// Reads an attribute, falling back to the `style="fill:...; stroke:..."`
/// shorthand which many export tools (Inkscape, Figma) use.
String? _attr(XmlElement el, String name) {
  final direct = el.getAttribute(name);
  if (direct != null && direct.trim().isNotEmpty) return direct.trim();
  final style = el.getAttribute('style');
  if (style == null || style.isEmpty) return null;
  for (final decl in style.split(';')) {
    final parts = decl.split(':');
    if (parts.length == 2 && parts[0].trim() == name) {
      final v = parts[1].trim();
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

double? _attrNum(XmlElement el, String name) {
  final v = _attr(el, name);
  return v == null ? null : double.tryParse(v);
}

/// Resolves an SVG fill/stroke value into a hex color string.
/// Handles hex colors, rgb(), named colors, `url(#gradient)` references
/// (uses the first stop color as a flat approximation), `none` and
/// `transparent`. Returns null for no paint / unknown references.
String? _resolveColor(String? raw, Map<String, String> gradients) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == 'none' || s == 'transparent') return null;
  final url = RegExp(r'url\(\s*#([^)]+)\s*\)').firstMatch(s);
  if (url != null) return gradients[url.group(1)];
  return _parseColor(s);
}

/// Scans `<defs>` for linear/radial gradients and maps id -> first stop color.
Map<String, String> _collectGradients(XmlDocument doc) {
  final out = <String, String>{};
  for (final el in doc.descendants.whereType<XmlElement>()) {
    final tag = el.name.local.toLowerCase();
    if (tag != 'lineargradient' && tag != 'radialgradient') continue;
    final id = el.getAttribute('id');
    if (id == null || id.isEmpty) continue;
    for (final stop in el.childElements) {
      if (stop.name.local.toLowerCase() != 'stop') continue;
      final c = _resolveColor(_attr(stop, 'stop-color') ?? '#000000', out);
      if (c != null) {
        out[id] = c;
        break;
      }
    }
  }
  return out;
}

String? _parseColor(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'none' || s == 'transparent') return null;
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => c * 2).join();
    if (hex.length != 6) return null;
    if (int.tryParse(hex, radix: 16) == null) return null;
    return '#$hex';
  }
  if (s.startsWith('rgb')) {
    final nums = RegExp(r'[\d.]+')
        .allMatches(s)
        .map((m) => double.tryParse(m.group(0)!))
        .toList();
    if (nums.length >= 3 && nums.every((v) => v != null)) {
      String two(int v) => v.toRadixString(16).padLeft(2, '0');
      return '#${two(nums[0]!.round().clamp(0, 255))}'
          '${two(nums[1]!.round().clamp(0, 255))}'
          '${two(nums[2]!.round().clamp(0, 255))}';
    }
  }
  return _namedColors[s];
}

const Map<String, String> _namedColors = {
  'black': '#000000',
  'white': '#ffffff',
  'red': '#ff0000',
  'green': '#008000',
  'blue': '#0000ff',
  'yellow': '#ffff00',
  'cyan': '#00ffff',
  'magenta': '#ff00ff',
  'gray': '#808080',
  'grey': '#808080',
  'orange': '#ffa500',
  'purple': '#800080',
  'brown': '#a52a2a',
  'pink': '#ffc0cb',
  'gold': '#ffd700',
  'silver': '#c0c0c0',
  'navy': '#000080',
  'teal': '#008080',
  'lime': '#00ff00',
  'maroon': '#800000',
  'olive': '#808000',
  'indigo': '#4b0082',
  'violet': '#ee82ee',
  'coral': '#ff7f50',
  'salmon': '#fa8072',
  'beige': '#f5f5dc',
  'tomato': '#ff6347',
};

// ---------------------------------------------------------------------------
// Shape outline extraction -> points (uses path metrics for flattening)
// ---------------------------------------------------------------------------

List<Point2>? _shapeOutline(XmlElement el, _M t) {
  final tag = el.name.local.toLowerCase();
  final p = _shapePath(el, tag);
  if (p == null) return null;
  final closed = _shapeClosed(tag);
  final pts = _flatten(p, closed);
  if (pts.length < 2) return null;
  if (!t.isIdentity) {
    return pts.map((pt) {
      final o = _apply(t, pt);
      return Point2(o.dx, o.dy);
    }).toList();
  }
  return pts;
}

ui.Path? _shapePath(XmlElement el, String tag) {
  final p = ui.Path();
  switch (tag) {
    case 'path':
      final d = el.getAttribute('d');
      if (d == null || d.isEmpty) return null;
      if (!_buildPathFromData(p, d)) return null;
      return p;
    case 'rect':
      final x = _num(el, 'x') ?? 0;
      final y = _num(el, 'y') ?? 0;
      final w = _num(el, 'width') ?? 0;
      final h = _num(el, 'height') ?? 0;
      if (w <= 0 || h <= 0) return null;
      p.addRect(ui.Rect.fromLTWH(x, y, w, h));
      return p;
    case 'circle':
      final cx = _num(el, 'cx') ?? 0;
      final cy = _num(el, 'cy') ?? 0;
      final r = _num(el, 'r') ?? 0;
      if (r <= 0) return null;
      p.addOval(ui.Rect.fromCircle(center: ui.Offset(cx, cy), radius: r));
      return p;
    case 'ellipse':
      final cx = _num(el, 'cx') ?? 0;
      final cy = _num(el, 'cy') ?? 0;
      final rx = _num(el, 'rx') ?? 0;
      final ry = _num(el, 'ry') ?? 0;
      if (rx <= 0 || ry <= 0) return null;
      p.addOval(ui.Rect.fromCenter(
          center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2));
      return p;
    case 'polygon':
    case 'polyline':
      final pts = _parsePoints(el.getAttribute('points'));
      if (pts.length < 2) return null;
      p.addPolygon(pts, tag == 'polygon');
      return p;
    case 'line':
      p.moveTo(_num(el, 'x1') ?? 0, _num(el, 'y1') ?? 0);
      p.lineTo(_num(el, 'x2') ?? 0, _num(el, 'y2') ?? 0);
      return p;
    default:
      return null;
  }
}

bool _buildPathFromData(ui.Path p, String d) {
  final tokens = _tokenize(d);
  if (tokens.isEmpty) return false;
  var idx = 0;
  double cx = 0, cy = 0;
  double sx = 0, sy = 0;
  double? pcx, pcy, pqx, pqy;
  String last = '';
  try {
    while (idx < tokens.length) {
      String cmd;
      if (tokens[idx].type == _T.char) {
        cmd = tokens[idx].ch;
        last = cmd;
        idx++;
      } else {
        cmd = last;
      }
      final isAbs = cmd == cmd.toUpperCase();
      final upper = cmd.toUpperCase();
      if (upper == 'Z') {
        cx = sx;
        cy = sy;
        p.close();
        pcx = pcy = pqx = pqy = null;
        continue;
      }
      final n = _argCount(upper);
      final args = <double>[];
      var need = n;
      while (need > 0 && idx < tokens.length && tokens[idx].type == _T.num) {
        args.add(tokens[idx].num);
        idx++;
        need--;
      }
      if (args.length < n) {
        if (args.isEmpty) return false;
        // pad for safety; most parsers handle partial groups by reusing last
      }
      switch (upper) {
        case 'M':
          cx = isAbs ? args[0] : cx + args[0];
          cy = isAbs ? args[1] : cy + args[1];
          sx = cx;
          sy = cy;
          p.moveTo(cx, cy);
          pcx = pcy = pqx = pqy = null;
          break;
        case 'L':
          cx = isAbs ? args[0] : cx + args[0];
          cy = isAbs ? args[1] : cy + args[1];
          p.lineTo(cx, cy);
          pcx = pcy = pqx = pqy = null;
          break;
        case 'H':
          cx = isAbs ? args[0] : cx + args[0];
          p.lineTo(cx, cy);
          pcx = pcy = pqx = pqy = null;
          break;
        case 'V':
          cy = isAbs ? args[0] : cy + args[0];
          p.lineTo(cx, cy);
          pcx = pcy = pqx = pqy = null;
          break;
        case 'C':
          final c1x = isAbs ? args[0] : cx + args[0];
          final c1y = isAbs ? args[1] : cy + args[1];
          final c2x = isAbs ? args[2] : cx + args[2];
          final c2y = isAbs ? args[3] : cy + args[3];
          final ex = isAbs ? args[4] : cx + args[4];
          final ey = isAbs ? args[5] : cy + args[5];
          p.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
          pcx = c2x;
          pcy = c2y;
          pqx = pqy = null;
          cx = ex;
          cy = ey;
          break;
        case 'S':
          final c1x = pcx != null ? 2 * cx - pcx : cx;
          final c1y = pcy != null ? 2 * cy - pcy : cy;
          final c2x = isAbs ? args[0] : cx + args[0];
          final c2y = isAbs ? args[1] : cy + args[1];
          final ex = isAbs ? args[2] : cx + args[2];
          final ey = isAbs ? args[3] : cy + args[3];
          p.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
          pcx = c2x;
          pcy = c2y;
          pqx = pqy = null;
          cx = ex;
          cy = ey;
          break;
        case 'Q':
          final qx = isAbs ? args[0] : cx + args[0];
          final qy = isAbs ? args[1] : cy + args[1];
          final ex = isAbs ? args[2] : cx + args[2];
          final ey = isAbs ? args[3] : cy + args[3];
          p.quadraticBezierTo(qx, qy, ex, ey);
          pqx = qx;
          pqy = qy;
          pcx = pcy = null;
          cx = ex;
          cy = ey;
          break;
        case 'T':
          final qx = pqx != null ? 2 * cx - pqx : cx;
          final qy = pqy != null ? 2 * cy - pqy : cy;
          final ex = isAbs ? args[0] : cx + args[0];
          final ey = isAbs ? args[1] : cy + args[1];
          p.quadraticBezierTo(qx, qy, ex, ey);
          pqx = qx;
          pqy = qy;
          pcx = pcy = null;
          cx = ex;
          cy = ey;
          break;
        case 'A':
          final res = _arcTo(
            p,
            cx,
            cy,
            rx: args[0],
            ry: args[1],
            rot: args[2],
            large: args[3] != 0,
            sweep: args[4] != 0,
            x: isAbs ? args[5] : cx + args[5],
            y: isAbs ? args[6] : cy + args[6],
          );
          cx = res.dx;
          cy = res.dy;
          pcx = pcy = pqx = pqy = null;
          break;
      }
    }
  } catch (_) {
    return false;
  }
  return true;
}

int _argCount(String upper) => switch (upper) {
      'M' || 'L' || 'T' => 2,
      'H' || 'V' => 1,
      'C' || 'S' => 6,
      'Q' || 'A' => 4,
      _ => 0,
    };

// SVG arc -> cubic beziers (metrics flatten the curves to points).
ui.Offset _arcTo(
  ui.Path p,
  double x0,
  double y0, {
  required double rx,
  required double ry,
  required double rot,
  required bool large,
  required bool sweep,
  required double x,
  required double y,
}) {
  rx = rx.abs();
  ry = ry.abs();
  if (rx == 0 || ry == 0) {
    p.lineTo(x, y);
    return ui.Offset(x, y);
  }
  if ((x0 - x).abs() < 1e-9 && (y0 - y).abs() < 1e-9) {
    return ui.Offset(x, y);
  }
  final rad = rot * math.pi / 180;
  final cosr = math.cos(rad);
  final sinr = math.sin(rad);
  final dx = (x0 - x) / 2;
  final dy = (y0 - y) / 2;
  final x1p = cosr * dx + sinr * dy;
  final y1p = -sinr * dx + cosr * dy;
  var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
  }
  final sign = large == sweep ? -1.0 : 1.0;
  final n1 = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  var cxp = 0.0;
  var cyp = 0.0;
  if (n1 > 0) {
    final base = math.sqrt((rx * rx * ry * ry - n1) / n1);
    cxp = sign * base * (rx * y1p / ry);
    cyp = sign * base * (-(ry * x1p) / rx);
  }
  final cx = cosr * cxp - sinr * cyp + (x0 + x) / 2;
  final cy = sinr * cxp + cosr * cyp + (y0 + y) / 2;
  final ux = (x1p - cxp) / rx;
  final uy = (y1p - cyp) / ry;
  final vx = (-x1p - cxp) / rx;
  final vy = (-y1p - cyp) / ry;

  double ang(double ax, double ay, double bx, double by) {
    final len = math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
    if (len == 0) return 0;
    final a = math.acos(((ax * bx + ay * by) / len).clamp(-1.0, 1.0));
    return ax * by - ay * bx < 0 ? -a : a;
  }

  final theta1 = ang(1, 0, ux, uy);
  var dtheta = ang(ux, uy, vx, vy) % (2 * math.pi);
  if (!sweep && dtheta > 0) dtheta -= 2 * math.pi;
  if (sweep && dtheta < 0) dtheta += 2 * math.pi;

  final segments = (dtheta.abs() / (math.pi / 2)).ceil().clamp(1, 4);
  final dthetaSeg = dtheta / segments;
  final cfs = 4 / 3 * math.tan(dthetaSeg / 4);
  final bx = cosr * rx;
  final by = sinr * rx;
  final cxm = -sinr * ry;
  final cym = cosr * ry;
  var lastX = 0.0;
  var lastY = 0.0;
  for (var i = 0; i < segments; i++) {
    final a1 = theta1 + i * dthetaSeg;
    final a3 = theta1 + (i + 1) * dthetaSeg;
    final cos1 = math.cos(a1);
    final sin1 = math.sin(a1);
    final cos3 = math.cos(a3);
    final sin3 = math.sin(a3);
    final x1 = bx * cos1 + cxm * sin1 + cx;
    final y1 = by * cos1 + cym * sin1 + cy;
    final x3 = bx * cos3 + cxm * sin3 + cx;
    final y3 = by * cos3 + cym * sin3 + cy;
    if (i == 0) p.lineTo(x1, y1);
    final tx = -bx * sin1 + cxm * cos1;
    final ty = -by * sin1 + cym * cos1;
    final tx3 = -bx * sin3 + cxm * cos3;
    final ty3 = -by * sin3 + cym * cos3;
    p.cubicTo(
        x1 + cfs * tx, y1 + cfs * ty, x3 - cfs * tx3, y3 - cfs * ty3, x3, y3);
    lastX = x3;
    lastY = y3;
  }
  return ui.Offset(lastX, lastY);
}

List<Point2> _flatten(ui.Path p, bool closed) {
  final out = <Point2>[];
  final metrics = p.computeMetrics().toList();
  for (final m in metrics) {
    final len = m.length;
    final step = _stepFor(len);
    var d = 0.0;
    while (d <= len) {
      final t = m.getTangentForOffset(math.min(d, len));
      if (t != null) {
        final pos = t.position;
        if (out.isEmpty ||
            (out.last.x - pos.dx).abs() > 0.01 ||
            (out.last.y - pos.dy).abs() > 0.01) {
          out.add(Point2(pos.dx, pos.dy));
        }
      }
      if (d >= len) break;
      d += step;
    }
  }
  if (closed && out.length >= 2) {
    final last = out.last;
    final first = out.first;
    if ((last.x - first.x).abs() > 0.01 || (last.y - first.y).abs() > 0.01) {
      out.add(first.clone());
    }
  }
  return out;
}

double _stepFor(double len) {
  if (len <= 0) return 1;
  return len / math.max(20, (len * 0.12).round()).toDouble();
}

// ---------------------------------------------------------------------------
// Transform parsing (2D affine)
// ---------------------------------------------------------------------------

class _M {
  final double a, b, c, d, e, f; // x'=a*x+c*y+e ; y'=b*x+d*y+f
  const _M.identity() : a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
  const _M(this.a, this.b, this.c, this.d, this.e, this.f);

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  _M compose(_M o) => _M(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );
}

ui.Offset _apply(_M m, Point2 pt) => ui.Offset(
      m.a * pt.x + m.c * pt.y + m.e,
      m.b * pt.x + m.d * pt.y + m.f,
    );

_M _parseTransform(XmlElement el) {
  final raw = el.getAttribute('transform');
  var m = _M.identity();
  if (raw == null || raw.isEmpty) return m;
  final matches = RegExp(r'([A-Za-z]+)\s*\(([^)]*)\)').allMatches(raw);
  for (final match in matches) {
    final name = match.group(1)!.toLowerCase();
    final args = RegExp(r'[-\d.eE]+')
        .allMatches(match.group(2)!)
        .map((x) => double.parse(x.group(0)!))
        .toList();
    if (args.isEmpty) continue;
    m = switch (name) {
      'translate' =>
        m.compose(_M(1, 0, 0, 1, args[0], args.length > 1 ? args[1] : 0)),
      'scale' =>
        m.compose(_M(args[0], 0, 0, args.length > 1 ? args[1] : args[0], 0, 0)),
      'rotate' when args.length == 1 => m.compose(_rot(args[0])),
      'rotate' => m.compose(_rotAbout(args[0], args[1], args[2])),
      'matrix' when args.length >= 6 =>
        m.compose(_M(args[0], args[1], args[2], args[3], args[4], args[5])),
      'skewx' => m.compose(_M(1, 0, math.tan(args[0] * math.pi / 180), 1, 0, 0)),
      'skewy' => m.compose(_M(1, math.tan(args[0] * math.pi / 180), 0, 1, 0, 0)),
      _ => m,
    };
  }
  return m;
}

_M _rot(double deg) {
  final r = deg * math.pi / 180;
  return _M(math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0);
}

_M _rotAbout(double deg, double ox, double oy) =>
    _M.identity()
        .compose(_M(1, 0, 0, 1, ox, oy))
        .compose(_rot(deg).compose(_M(1, 0, 0, 1, -ox, -oy)));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<ui.Offset> _parsePoints(String? raw) {
  final out = <ui.Offset>[];
  if (raw == null) return out;
  final nums = RegExp(r'[-\d.eE]+')
      .allMatches(raw)
      .map((m) => double.tryParse(m.group(0)!))
      .toList();
  for (var i = 0; i + 1 < nums.length; i += 2) {
    final x = nums[i];
    final y = nums[i + 1];
    if (x != null && y != null) out.add(ui.Offset(x, y));
  }
  return out;
}

double? _num(XmlElement el, String attr) {
  final v = el.getAttribute(attr);
  return v == null ? null : double.tryParse(v);
}

enum _T { char, num }

class _Tok {
  final _T type;
  final String ch;
  final double num;
  const _Tok.char(this.ch) : type = _T.char, num = 0;
  const _Tok.num(this.num) : type = _T.num, ch = '';
}

List<_Tok> _tokenize(String d) {
  final out = <_Tok>[];
  final re =
      RegExp(r'([AaCcHhLlMmQqSsTtVvZz])|([+\-]?(?:\d*\.)?\d+(?:[eE][+\-]?\d+)?)');
  for (final m in re.allMatches(d)) {
    if (m.group(1) != null) {
      out.add(_Tok.char(m.group(1)!));
    } else if (m.group(2) != null) {
      out.add(_Tok.num(double.parse(m.group(2)!)));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Figure construction
// ---------------------------------------------------------------------------

Figure _buildFigure(
  List<SvgLayer> layers, {
  required double canvasWidth,
  required double canvasHeight,
}) {
  final all = <Point2>[];
  for (final layer in layers) {
    for (final shape in layer.shapes) {
      all.addAll(shape);
    }
  }
  if (all.isEmpty) {
    final empty = Figure();
    empty.points.clear();
    empty.rootIndices.clear();
    return empty;
  }
  final fit = _fitToCanvas(
    all,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );
  Point2 map(Point2 p) => fit.map(p);

  final figure = Figure();
  figure.points.clear();
  final roots = <int>[];
  for (final layer in layers) {
    var firstIdx = -1;
    for (var s = 0; s < layer.shapes.length; s++) {
      final shape = layer.shapes[s];
      final segColor = layer.fills[s] ?? layer.strokes[s] ?? '#000000';
      final startIdx = figure.points.length;
      if (firstIdx < 0) firstIdx = startIdx;
      final mapped = shape.map(map);
      figure.points.addAll(mapped);
      final isClosed = layer.closed[s];
      for (var i = 0; i < mapped.length - 1; i++) {
        figure.segments.add(Segment('line')
          ..point1Index = startIdx + i
          ..point2Index = startIdx + i + 1
          ..color = segColor
          ..width = 2
          ..layer = figure.segments.length);
      }
      if (isClosed && mapped.length > 2) {
        figure.segments.add(Segment('line')
          ..point1Index = startIdx + mapped.length - 1
          ..point2Index = startIdx
          ..color = segColor
          ..width = 2
          ..layer = figure.segments.length);
      }
      // Connect separate sub-paths within the same layer with an invisible
      // 'none' segment so the layer stays one connected component (parenting /
      // transform works) without drawing a visible line.
      if (s < layer.shapes.length - 1) {
        final nextStart = startIdx + mapped.length;
        figure.segments.add(Segment('none')
          ..point1Index = startIdx + mapped.length - 1
          ..point2Index = nextStart
          ..layer = figure.segments.length);
      }
    }
    if (firstIdx >= 0 &&
        firstIdx < figure.points.length &&
        !roots.contains(firstIdx)) {
      roots.add(firstIdx);
    }
  }
  figure.rootIndices..clear()..addAll(roots);
  figure.ensureSegmentsInDefaultGroup();
  return figure;
}

// ---------------------------------------------------------------------------
// Layer -> PNG rasterization (used by the "as assets" import mode)
// ---------------------------------------------------------------------------

Future<Uint8List?> _renderLayerPng(
  SvgLayer layer,
  _LayerBox box, {
  required double renderScale,
}) async {
  final pixelW = math.max((box.width * renderScale).round(), 1);
  final pixelH = math.max((box.height * renderScale).round(), 1);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.scale(pixelW / box.width, pixelH / box.height);
  canvas.translate(-box.minX, -box.minY);

  for (var i = 0; i < layer.shapes.length; i++) {
    final shape = layer.shapes[i];
    final isClosed = layer.closed[i];
    final path = ui.Path();
    if (shape.isEmpty) continue;
    path.moveTo(shape.first.x, shape.first.y);
    for (var j = 1; j < shape.length; j++) {
      path.lineTo(shape[j].x, shape[j].y);
    }
    if (isClosed) path.close();

    // One PNG, but preserve each shape's own fill and stroke so the part
    // isn't painted flat black (the previous bug) or with a single colour.
    final fill = layer.fills[i];
    if (fill != null) {
      canvas.drawPath(path, ui.Paint()..color = _parseUiColor(fill));
    }
    final stroke = layer.strokes[i];
    if (stroke != null) {
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = _parseUiColor(stroke)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (layer.strokeWidths[i] ?? 2.0)
          ..strokeJoin = ui.StrokeJoin.round
          ..strokeCap = ui.StrokeCap.round,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelW, pixelH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return byteData?.buffer.asUint8List();
}

ui.Color _parseUiColor(String hex) {
  var s = hex.replaceAll('#', '');
  if (s.length == 3) {
    s = s.split('').map((c) => c * 2).join();
  }
  if (s.length != 6) return const ui.Color(0xFF000000);
  final v = int.tryParse(s, radix: 16) ?? 0;
  return ui.Color(0xFF000000 | v);
}
