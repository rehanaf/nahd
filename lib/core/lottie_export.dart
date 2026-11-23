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
///    `ty: "sh"` shapes whose vertices are sampled from [data.keyframes] for
///    every point track so movement interpolates like the in-app timeline.
///  * `image` segments become `ty: 2` layered assets (image size is read from
///    the decoded bitmap so height:auto resolves correctly).
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

  /// The union of every keyframe time across all point tracks, in frames.
  List<int> get _sampleTimes {
    final times = <int>{0, _duration.toInt()};
    if (animation != null) {
      for (final t in animation!.tracks) {
        for (final kf in t.keyframes) {
          times.add(kf.time.round());
        }
      }
    }
    final sorted = times.toList()..sort();
    return sorted;
  }

  /// A posed copy of [figure] at [frame] (no easing: stored keyframes are the
  /// interpolation targets, Lottie re-interpolates them).
  Figure _posedAt(int frame) {
    final posed = figure.clone();
    final anim = animation;
    if (anim != null) {
      anim.applyToFigure(posed, frame.toDouble(), false);
    }
    return posed;
  }

  Segment? _posedSegmentOf(Figure posed, Segment source, int point1Index) {
    for (final s in posed.segments) {
      if ((s.point1Index == source.point1Index &&
          s.point2Index == source.point2Index)) {
        return s;
      }
    }
    return null;
  }

  /// Builds the Lottie JSON document.
  Future<String> exportJson() async {
    final poses = <int, Figure>{for (final t in _sampleTimes) t: _posedAt(t)};
    final layers = <Map<String, dynamic>>[];
    var zIndex = 0;

    final segs = figure.segmentsInDrawOrder();
    final usedImages = <String>{};

    for (final seg in segs) {
      final p1i = seg.point1Index;
      final p2i = seg.point2Index;
      if (p1i >= figure.points.length || p2i >= figure.points.length) continue;

      if (seg.type == 'line' || seg.type == 'circle') {
        final shape = _buildShapeShape(seg, _sampleTimes, poses, p1i, p2i);
        if (shape != null) {
          layers.add({
            'ddd': 0,
            'ind': zIndex++,
            'ty': 4,
            'nm': seg.id,
            'sr': 1,
            'ks': _staticTransform(),
            'ao': 0,
            'shapes': [shape],
            'ip': 0,
            'op': _duration,
            'st': 0,
            'bm': 0,
          });
        }
      } else if (seg.type == 'image') {
        final uri = seg.imageDataList.isNotEmpty
            ? seg.imageDataList[
                seg.activeImageIndex.clamp(0, seg.imageDataList.length - 1)]
            : null;
        if (uri == null || uri.isEmpty) continue;
        usedImages.add(uri);
        final dims = await _imageSizeOf(uri);
        final assetW = dims?.$1 ?? 1.0;
        final assetH = dims?.$2 ?? 1.0;
        final layerW = seg.imageWidth is num
            ? (seg.imageWidth as num).toDouble()
            : 100.0;
        final layerH = seg.imageHeight == 'auto'
            ? layerW * assetH / math.max(1, assetW)
            : seg.imageHeight is num
                ? (seg.imageHeight as num).toDouble()
                : 100.0;
        // Static transform centred on the segment midpoint (image offset is
        // carried into the anchor as a Lottie offset).
        final posed0 = poses[0]!;
        final p1 = posed0.points[seg.point1Index];
        final p2 = posed0.points[seg.point2Index];
        final midX = (p1.x + p2.x) / 2 + seg.imageOffsetX;
        final midY = (p1.y + p2.y) / 2 + seg.imageOffsetY;
        final segAngle =
            (math.atan2(p2.y - p1.y, p2.x - p1.x) * 180 / math.pi +
                    seg.imageRotate)
                .toDouble();
        layers.add({
          'ddd': 0,
          'ind': zIndex++,
          'ty': 2,
          'nm': seg.id,
          'sr': 1,
          'refId': 'img_${usedImages.length - 1}',
          'ks': {
            'o': {'a': 0, 'k': 100},
            'r': {'a': 0, 'k': segAngle},
            'p': {
              'a': 0,
              'k': [midX, midY, 0]
            },
            'a': {
              'a': 0,
              'k': [layerW / 2, layerH / 2, 0]
            },
            's': {
              'a': 0,
              'k': [
                layerW / math.max(1, assetW) * 100,
                layerH / math.max(1, assetH) * 100,
                100,
              ]
            },
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

  List<double> _samplePath(Figure posed, Segment seg, int p1i, int p2i) {
    final p1 = posed.points[p1i];
    final p2 = posed.points[p2i];
    final pts = <double>[];
    if (seg.type == 'circle') {
      // Approximate the ellipse as a 24-gon read from the posed points.
      final cx = (p1.x + p2.x) / 2;
      final cy = (p1.y + p2.y) / 2;
      final rx = (p2.x - p1.x).abs() / 2;
      final ry = (p2.y - p1.y).abs() / 2;
      for (var k = 0; k < 24; k++) {
        final a = k / 24 * 2 * math.pi;
        pts.add(cx + math.cos(a) * rx);
        pts.add(cy + math.sin(a) * ry);
      }
    } else {
      pts.addAll([p1.x, p1.y, p2.x, p2.y]);
      if (seg.curved && seg.controlDX != null && seg.controlDY != null) {
        final cx = (p1.x + p2.x) / 2 + seg.controlDX!;
        final cy = (p1.y + p2.y) / 2 + seg.controlDY!;
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
    final kfs = <Map<String, dynamic>>[];
    for (final t in times) {
      final posed = poses[t]!;
      final posedSeg = _posedSegmentOf(posed, seg, p1i);
      if (posedSeg == null) continue;
      final pts = _samplePath(posed, posedSeg, p1i, p2i);
      kfs.add({
        't': t,
        's': _pathValue(pts, closed),
      });
    }
    if (kfs.isEmpty) return null;

    Map<String, dynamic> ks;
    if (kfs.length == 1) {
      ks = {'a': 0, 'k': kfs.first['s']};
    } else {
      ks = {'a': 1, 'k': kfs};
    }
    final strokeColor = _toLottieColor(seg.color);
    final fill = seg.filled || seg.type == 'circle'
        ? (seg.fillColor != null && seg.fillColor!.trim().isNotEmpty
            ? _toLottieColor(seg.fillColor!)
            : strokeColor)
        : null;
    final shapes = <Map<String, dynamic>>[
      {
        'ty': 'gr',
        'nm': 'shape',
        'it': [
          {
            'ty': 'sh',
            'nm': 'path',
            'ks': ks,
          },
          if (fill != null)
            {
              'ty': 'fl',
              'nm': 'fill',
              'c': {'a': 0, 'k': fill},
              'o': {'a': 0, 'k': 100},
              'r': 1,
            },
          {
            'ty': 'st',
            'nm': 'stroke',
            'c': {'a': 0, 'k': strokeColor},
            'o': {'a': 0, 'k': 100},
            'w': {'a': 0, 'k': seg.width <= 0 ? 1 : seg.width},
            'lc': seg.lineCap == 'butt'
                ? 1
                : seg.lineCap == 'square'
                    ? 2
                    : 2,
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
      },
    ];
    return shapes.first;
  }

  List<double> _toLottieColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length >= 6) {
      return [
        int.parse(h.substring(0, 2), radix: 16) / 255,
        int.parse(h.substring(2, 4), radix: 16) / 255,
        int.parse(h.substring(4, 6), radix: 16) / 255,
      ];
    }
    return [0, 0, 0];
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