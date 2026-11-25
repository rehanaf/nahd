import 'dart:convert';
import 'dart:math' as math;

import 'models/figure.dart';
import 'models/figure_animation.dart';
import 'models/segment.dart';
import 'render/figure_render.dart';

/// Exports a rig + animation to a minimal Lottie (bodymovin) JSON document.
///
/// Coverage:
///  * `line` / `circle` (and their curve variants) segments become animated
///    `ty: "sh"` shapes. Vertices and curve handles are sampled from the point
///    tracks; stroke/fill/width/visibility are sampled from the same per-frame
///    overrides the editor uses, so a preset exported after auto-keying looks
///    identical to the canvas at every frame.
///  * `image` segments become `ty: 2` layered assets with animated position,
///    rotation, scale and opacity.
///  * `text` segments are skipped (Lottie text layers would need font assets).
///
/// All points render in a single coordinate space (Lottie has no scene graph
/// hierarchy for our rig), so articulations export as flat, absolute geometry.
class LottieExporter {
  final Figure figure;
  final FigureAnimation? animation;

  LottieExporter(this.figure, [this.animation]);

  int get _fps => figure.fps <= 0 ? 12 : figure.fps.round();

  double get _duration =>
      animation == null ? 1 : math.max(1, animation!.duration);

  /// Every frame where any point track, visibility/opacity/colour track,
  /// image switch or generic override changes. A frame immediately before each
  /// change is included as well so hold-style edits (hidden, curve toggle,
  /// width...) become hard steps instead of smooth interpolations.
  List<int> get _sampleTimes {
    final times = <int>{0, _duration.toInt()};

    void addTime(dynamic raw) {
      final t = (raw as num?)?.round();
      if (t == null || t < 0 || t > _duration.ceil()) return;
      times.add(t);
      if (t > 0) times.add(t - 1);
    }

    if (animation != null) {
      for (final track in animation!.tracks) {
        for (final kf in track.keyframes) {
          addTime(kf.time);
        }
      }
    }
    for (final track in figure.visibility.values) {
      for (final kf in track) {
        addTime(kf.time);
      }
    }
    for (final track in figure.opacity.values) {
      for (final kf in track) {
        addTime(kf.time);
      }
    }
    for (final track in figure.colors.values) {
      for (final kf in track) {
        addTime(kf.time);
      }
    }
    for (final track in figure.segmentImages.values) {
      for (final kf in track) {
        addTime(kf.time);
      }
    }
    for (final frame in figure.frameOverrides.keys) {
      addTime(frame);
    }

    final sorted = times.toList()..sort();
    return sorted;
  }

  /// A posed copy of [figure] at [frame] (no easing: stored keyframes are the
  /// interpolation targets, Lottie re-interpolates them). `clone()` carries the
  /// per-frame overrides, so [Figure.styleFor] works on the copy too.
  Figure _posedAt(int frame) {
    final posed = figure.clone();
    final anim = animation;
    if (anim != null) {
      anim.applyToFigure(posed, frame.toDouble(), false);
    }
    return posed;
  }

  Segment? _posedSegmentOf(Figure posed, Segment source) {
    for (final s in posed.segments) {
      if (s.id == source.id) return s;
    }
    // Legacy figures can contain duplicate ids; fall back to endpoints.
    for (final s in posed.segments) {
      if (s.point1Index == source.point1Index &&
          s.point2Index == source.point2Index) {
        return s;
      }
    }
    return null;
  }

  SegmentFrameStyle _styleAt(Figure fig, Segment seg, int frame) =>
      fig.styleFor(seg, frame.toDouble(), enabled: true);

  bool _visibleAt(Figure fig, Segment seg, int frame) {
    final style = _styleAt(fig, seg, frame);
    if (style.hidden) return false;
    return fig.getFigureVisibility(
      fig.segmentFigureKey(seg),
      frame.toDouble(),
    );
  }

  double _opacityAt(Figure fig, Segment seg, int frame) {
    if (!_visibleAt(fig, seg, frame)) return 0;
    return fig.getFigureOpacity(
          fig.segmentFigureKey(seg),
          frame.toDouble(),
        ) *
        100;
  }

  String _strokeAt(Figure fig, Segment seg, int frame) {
    final style = _styleAt(fig, seg, frame);
    final over = fig.getFigureColorOverride(
      fig.segmentFigureKey(seg),
      frame.toDouble(),
    );
    return over ?? style.color;
  }

  String _fillAt(Figure fig, Segment seg, int frame) {
    final style = _styleAt(fig, seg, frame);
    final over = fig.getFigureColorOverride(
      fig.segmentFigureKey(seg),
      frame.toDouble(),
    );
    return over ?? style.fillColor ?? style.color;
  }

  String? _imageUriAt(Figure fig, Segment seg, int frame) {
    if (seg.imageDataList.isEmpty) return null;
    final index = fig.getSegmentImageIndex(seg.id, frame.toDouble()) ??
        seg.activeImageIndex;
    if (index < 0 || index >= seg.imageDataList.length) return null;
    final uri = seg.imageDataList[index];
    return uri.isEmpty ? null : uri;
  }

  /// Builds the Lottie JSON document.
  Future<String> exportJson() async {
    final times = _sampleTimes;
    final poses = <int, Figure>{for (final t in times) t: _posedAt(t)};
    final layers = <Map<String, dynamic>>[];
    var zIndex = 0;

    final segs = figure.segmentsInDrawOrder();
    final usedImages = <String>{};

    for (final seg in segs) {
      final p1i = seg.point1Index;
      final p2i = seg.point2Index;
      if (p1i >= figure.points.length || p2i >= figure.points.length) continue;

      if (seg.type == 'line' || seg.type == 'circle') {
        final shape = _buildShapeShape(seg, times, poses, p1i, p2i);
        if (shape != null) {
          final transform = _staticTransform();
          transform['o'] = _animatedScalar(
            times,
            (t) => _opacityAt(figure, seg, t),
          );
          layers.add({
            'ddd': 0,
            'ind': zIndex++,
            'ty': 4,
            'nm': seg.id,
            'sr': 1,
            'ks': transform,
            'ao': 0,
            'shapes': [shape],
            'ip': 0,
            'op': _duration,
            'st': 0,
            'bm': 0,
          });
        }
      } else if (seg.type == 'image') {
        String? uri;
        for (final t in times) {
          uri = _imageUriAt(figure, seg, t);
          if (uri != null) break;
        }
        if (uri == null) continue;
        usedImages.add(uri);
        final dims = await _imageSizeOf(uri);
        final assetW = dims?.$1.toDouble() ?? 1.0;
        final assetH = dims?.$2.toDouble() ?? 1.0;

        layers.add({
          'ddd': 0,
          'ind': zIndex++,
          'ty': 2,
          'nm': seg.id,
          'sr': 1,
          'refId': 'img_${usedImages.length - 1}',
          'ks': {
            'o': _animatedScalar(times, (t) => _opacityAt(figure, seg, t)),
            'r': _animatedScalar(times, (t) {
              final posed = poses[t]!;
              final style = _styleAt(posed, seg, t);
              final p1 = posed.points[seg.point1Index];
              final p2 = posed.points[seg.point2Index];
              final segAngle =
                  math.atan2(p2.y - p1.y, p2.x - p1.x) * 180 / math.pi;
              return segAngle + style.imageRotate;
            }),
            'p': _animatedVector(times, (t) {
              final posed = poses[t]!;
              final style = _styleAt(posed, seg, t);
              final center = _segmentCenter(posed, seg, style);
              return [
                center.$1 + style.imageOffsetX,
                center.$2 + style.imageOffsetY,
                0,
              ];
            }),
            'a': _animatedVector(times, (t) {
              final style = _styleAt(poses[t]!, seg, t);
              final size = _lottieImageSize(style, assetW, assetH);
              return [size.$1 / 2, size.$2 / 2, 0];
            }),
            's': _animatedVector(times, (t) {
              final style = _styleAt(poses[t]!, seg, t);
              final size = _lottieImageSize(style, assetW, assetH);
              return [
                size.$1 / math.max(1, assetW) * 100,
                size.$2 / math.max(1, assetH) * 100,
                100,
              ];
            }),
          },
          'ao': 0,
          'ip': 0,
          'op': _duration,
          'st': 0,
          'bm': 0,
        });
      }
    }

    final assets = <Map<String, dynamic>>[];
    var imgIdx = 0;
    for (final uri in usedImages) {
      assets.add({
        'id': 'img_${imgIdx++}',
        'w': 100,
        'h': 100,
        'u': '',
        'p': uri,
        'e': 1,
      });
    }

    return jsonEncode({
      'v': '5.7.4',
      'fr': _fps,
      'ip': 0,
      'op': _duration,
      'w': figure.canvasWidth.toInt(),
      'h': figure.canvasHeight.toInt(),
      'nm': 'id-animate export',
      'ddd': 0,
      'assets': assets,
      'layers': layers,
      'markers': [],
    });
  }

  // ---------------------------------------------------------------------------
  // Lottie property helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _animatedScalar(
    List<int> times,
    double Function(int) valueAt, {
    double Function(double)? transform,
  }) {
    final raw = [for (final t in times) valueAt(t)];
    final values = transform == null ? raw : raw.map(transform).toList();
    if (values.every((v) => (v - values.first).abs() < 0.00001)) {
      return {'a': 0, 'k': values.first};
    }
    final keys = <Map<String, dynamic>>[];
    for (var i = 0; i < times.length; i++) {
      final key = <String, dynamic>{'t': times[i], 's': [values[i]]};
      if (i + 1 < times.length) {
        key['e'] = [values[i + 1]];
      }
      keys.add(key);
    }
    return {'a': 1, 'k': keys};
  }

  Map<String, dynamic> _animatedVector(
    List<int> times,
    List<double> Function(int) valueAt,
  ) {
    final values = [for (final t in times) valueAt(t)];
    if (values.every((v) => _sameVector(v, values.first))) {
      return {'a': 0, 'k': values.first};
    }
    final keys = <Map<String, dynamic>>[];
    for (var i = 0; i < times.length; i++) {
      final key = <String, dynamic>{'t': times[i], 's': values[i]};
      if (i + 1 < times.length) key['e'] = values[i + 1];
      keys.add(key);
    }
    return {'a': 1, 'k': keys};
  }

  bool _sameVector(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.00001) return false;
    }
    return true;
  }

  Map<String, dynamic> _animatedPath(
    Segment seg,
    List<int> times,
    Map<int, Figure> poses,
    int p1i,
    int p2i,
    bool closed,
  ) {
    final keys = <Map<String, dynamic>>[];
    Map<String, dynamic>? first;
    var allSame = true;

    for (final t in times) {
      final posed = poses[t]!;
      final posedSeg = _posedSegmentOf(posed, seg);
      if (posedSeg == null) continue;
      final style = _styleAt(posed, seg, t);
      final pts = _samplePath(posed, posedSeg, style, p1i, p2i);
      final value = _pathValue(pts, closed);
      first ??= value;

      if (value.toString() != first.toString()) allSame = false;
      keys.add({'t': t, 's': value});
    }
    if (keys.isEmpty) {
      final p1 = figure.points[p1i];
      final p2 = figure.points[p2i];
      return {
        'a': 0,
        'k': _pathValue([p1.x, p1.y, p2.x, p2.y], closed),
      };
    }
    if (allSame) return {'a': 0, 'k': first!};
    for (var i = 0; i + 1 < keys.length; i++) {
      keys[i]['e'] = keys[i + 1]['s'];
    }
    return {'a': 1, 'k': keys};
  }

  List<double> _samplePath(Figure posed, Segment seg, SegmentFrameStyle style,
      int p1i, int p2i) {
    final p1 = posed.points[p1i];
    final p2 = posed.points[p2i];
    final pts = <double>[];
    if (seg.type == 'circle') {
      // Approximate the ellipse as a 24-gon, matching the editor's curved
      // circle centre when a curve handle is active.
      final center = _segmentCenter(posed, seg, style);
      final cx = center.$1;
      final cy = center.$2;
      final rx = (p2.x - p1.x).abs() / 2;
      final ry = (p2.y - p1.y).abs() / 2;
      for (var k = 0; k < 24; k++) {
        final a = k / 24 * 2 * math.pi;
        pts.add(cx + math.cos(a) * rx);
        pts.add(cy + math.sin(a) * ry);
      }
    } else {
      pts.addAll([p1.x, p1.y, p2.x, p2.y]);
      if (style.curved) {
        final cx = style.controlDX != null
            ? (p1.x + p2.x) / 2 + style.controlDX!
            : (p1.x + p2.x) / 2 - (p2.y - p1.y) * style.curvature;
        final cy = style.controlDY != null
            ? (p1.y + p2.y) / 2 + style.controlDY!
            : (p1.y + p2.y) / 2 + (p2.x - p1.x) * style.curvature;
        pts.clear();
        const subdiv = 12;
        for (var k = 0; k <= subdiv; k++) {
          final tS = k / subdiv;
          final u = 1 - tS;
          pts.add(u * u * p1.x + 2 * u * tS * cx + tS * tS * p2.x);
          pts.add(u * u * p1.y + 2 * u * tS * cy + tS * tS * p2.y);
        }
      }
    }
    return pts;
  }

  /// Midpoint used by the renderer for curved segments (image and circle).
  (double, double) _segmentCenter(
    Figure fig,
    Segment seg,
    SegmentFrameStyle style,
  ) {
    final p1 = fig.points[seg.point1Index];
    final p2 = fig.points[seg.point2Index];
    var mx = (p1.x + p2.x) / 2;
    var my = (p1.y + p2.y) / 2;
    if (style.curved) {
      final cpx = style.controlDX != null
          ? mx + style.controlDX!
          : mx - (p2.y - p1.y) * style.curvature;
      final cpy = style.controlDY != null
          ? my + style.controlDY!
          : my + (p2.x - p1.x) * style.curvature;
      mx = (p1.x + p2.x) / 4 + cpx / 2;
      my = (p1.y + p2.y) / 4 + cpy / 2;
    }
    return (mx, my);
  }

  (double, double) _lottieImageSize(
    SegmentFrameStyle style,
    double assetW,
    double assetH,
  ) {
    final rawW = style.imageWidth is num
        ? (style.imageWidth as num).toDouble()
        : null;
    final rawH = style.imageHeight is num
        ? (style.imageHeight as num).toDouble()
        : null;
    final ar = assetW / math.max(1, assetH);
    if (rawW == null && rawH == null) {
      return (100, 100 / ar);
    }
    if (rawW == null) {
      final h = rawH!;
      return (h * ar, h);
    }
    if (rawH == null) {
      return (rawW, rawW / ar);
    }
    return (rawW, rawH);
  }

  /// path value object used by Lottie: vertices + in/out tangents + closed.
  Map<String, dynamic> _pathValue(List<double> pts, bool closed) {
    final i = <List<double>>[];
    final o = <List<double>>[];
    final v = <List<double>>[];
    for (var k = 0; k < pts.length; k += 2) {
      v.add([pts[k], pts[k + 1]]);
      i.add([0, 0]);
      o.add([0, 0]);
    }
    return {
      'i': i,
      'o': o,
      'v': v,
      'c': closed,
    };
  }

  Map<String, dynamic> _staticTransform() => {
        'o': {'a': 0, 'k': 100},
        'r': {'a': 0, 'k': 0},
        'p': {'a': 0, 'k': [0, 0, 0]},
        'a': {'a': 0, 'k': [0, 0, 0]},
        's': {'a': 0, 'k': [100, 100, 100]},
      };

  Map<String, dynamic>? _buildShapeShape(
    Segment seg,
    List<int> times,
    Map<int, Figure> poses,
    int p1i,
    int p2i,
  ) {
    final closed = seg.type == 'circle' || seg.shapeClosed;
    final ks = _animatedPath(seg, times, poses, p1i, p2i, closed);

    final anyFilled = times.any((t) => _styleAt(poses[t]!, seg, t).filled);
    final strokeColor = _animatedVector(
      times,
      (t) => _toLottieColor(_strokeAt(poses[t]!, seg, t)),
    );
    final strokeWidth = _animatedScalar(times, (t) {
      final w = _styleAt(poses[t]!, seg, t).width;
      return w <= 0 ? 3 : w;
    });
    final cap = _styleAt(figure, seg, 0).lineCap;
    final strokeCap = cap == 'butt' ? 1 : 2;

    final hasFill = anyFilled;
    final fillColor = hasFill
        ? _animatedVector(
            times,
            (t) => _toLottieColor(_fillAt(poses[t]!, seg, t)),
          )
        : null;
    final fillOpacity = hasFill
        ? _animatedScalar(
            times,
            (t) => _styleAt(poses[t]!, seg, t).filled ? 100.0 : 0.0,
          )
        : null;

    return {
      'ty': 'gr',
      'nm': 'shape',
      'it': [
        {
          'ty': 'sh',
          'nm': 'path',
          'ks': ks,
        },
        if (hasFill)
          {
            'ty': 'fl',
            'nm': 'fill',
            'c': fillColor,
            'o': fillOpacity,
            'r': 1,
          },
        {
          'ty': 'st',
          'nm': 'stroke',
          'c': strokeColor,
          'o': {'a': 0, 'k': 100},
          'w': strokeWidth,
          'lc': strokeCap,
          'lj': 2,
          'ml': 4,
        },
        {
          'ty': 'tr',
          'p': {'a': 0, 'k': [0, 0, 0]},
          'a': {'a': 0, 'k': [0, 0, 0]},
          's': {'a': 0, 'k': [100, 100, 100]},
          'r': {'a': 0, 'k': 0},
          'o': {'a': 0, 'k': 100},
          'sk': {'a': 0, 'k': 0},
          'sa': {'a': 0, 'k': 0},
        },
      ],
    };
  }

  List<double> _toLottieColor(String hex) {
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 3 || h.length == 4) {
      h = h.split('').map((c) => c * 2).join();
    }
    if (h.length < 6) return [0, 0, 0, 1];
    int parse(String part) => int.tryParse(part, radix: 16) ?? 0;
    final r = parse(h.substring(0, 2)) / 255;
    final g = parse(h.substring(2, 4)) / 255;
    final b = parse(h.substring(4, 6)) / 255;
    final a = h.length >= 8 ? parse(h.substring(6, 8)) / 255 : 1.0;
    return [r, g, b, a];
  }

  Future<(int, int)?> _imageSizeOf(String dataUri) async {
    try {
      final image = await decodeDataUriImage(dataUri);
      return (image.width, image.height);
    } catch (_) {
      return null;
    }
  }
}

/// Convenience entry point.
Future<String> exportLottieJson(Figure figure, FigureAnimation? animation) =>
    LottieExporter(figure, animation).exportJson();
