import 'dart:collection';

import '../json_utils.dart';
import 'segment.dart';

class CycleFill {
  bool filled;
  String? fillColor;

  CycleFill({this.filled = true, this.fillColor});

  Map<String, dynamic> toJson() => {
        'filled': filled,
        'fillColor': fillColor,
      };

  factory CycleFill.fromJson(Map<String, dynamic> json) => CycleFill(
        filled: json['filled'] as bool? ?? true,
        fillColor: json['fillColor'] as String?,
      );

  CycleFill clone() => CycleFill(filled: filled, fillColor: fillColor);
}

/// Resolves a segment's visual properties at one frame.
///
/// The base [Segment] always stores the newest value; a [Figure] may also
/// carry per-frame overrides written by the tools. This wrapper lets both the
/// editor painter and the exporters read exactly the same value for a frame.
class SegmentFrameStyle {
  final Figure figure;
  final Segment segment;
  final double time;
  final bool enabled;

  const SegmentFrameStyle(this.figure, this.segment, this.time,
      {this.enabled = true});

  String _key(String prop) => 'seg:${segment.id}:$prop';

  bool get hidden =>
      enabled ? figure.frameBool(_key('hidden'), time, segment.hidden) : segment.hidden;
  double get width =>
      enabled ? figure.frameDouble(_key('width'), time, segment.width) : segment.width;
  String get color =>
      enabled ? figure.frameString(_key('color'), time, segment.color) : segment.color;
  String? get fillColor => enabled
      ? figure.frameNullableString(_key('fillColor'), time, segment.fillColor)
      : segment.fillColor;
  String get lineCap => enabled
      ? figure.frameString(_key('lineCap'), time, segment.lineCap)
      : segment.lineCap;
  int get layer =>
      enabled ? figure.frameInt(_key('layer'), time, segment.layer) : segment.layer;
  bool get curved =>
      enabled ? figure.frameBool(_key('curved'), time, segment.curved) : segment.curved;
  double get curvature => enabled
      ? figure.frameDouble(_key('curvature'), time, segment.curvature)
      : segment.curvature;
  double? get controlDX => enabled
      ? figure.frameNullableDouble(_key('controlDX'), time, segment.controlDX)
      : segment.controlDX;
  double? get controlDY => enabled
      ? figure.frameNullableDouble(_key('controlDY'), time, segment.controlDY)
      : segment.controlDY;
  dynamic get imageWidth => enabled
      ? figure.frameObject(_key('imageWidth'), time, segment.imageWidth)
      : segment.imageWidth;
  dynamic get imageHeight => enabled
      ? figure.frameObject(_key('imageHeight'), time, segment.imageHeight)
      : segment.imageHeight;
  double get imageOffsetX => enabled
      ? figure.frameDouble(_key('imageOffsetX'), time, segment.imageOffsetX)
      : segment.imageOffsetX;
  double get imageOffsetY => enabled
      ? figure.frameDouble(_key('imageOffsetY'), time, segment.imageOffsetY)
      : segment.imageOffsetY;
  double get imageRotate => enabled
      ? figure.frameDouble(_key('imageRotate'), time, segment.imageRotate)
      : segment.imageRotate;
  bool get filled => enabled
      ? figure.frameBool(_key('filled'), time, segment.filled)
      : segment.filled;
  bool get isCollision => enabled
      ? figure.frameBool(_key('isCollision'), time, segment.isCollision)
      : segment.isCollision;
  String? get text => enabled
      ? figure.frameNullableString(_key('text'), time, segment.text)
      : segment.text;
  double get textSize => enabled
      ? figure.frameDouble(_key('textSize'), time, segment.textSize)
      : segment.textSize;
}

class VisibilityKeyframe {
  double time;
  bool visible;

  VisibilityKeyframe(this.time, this.visible);

  Map<String, dynamic> toJson() => {'time': time, 'visible': visible};

  factory VisibilityKeyframe.fromJson(Map<String, dynamic> json) =>
      VisibilityKeyframe(
        (json['time'] as num?)?.toDouble() ?? 0,
        json['visible'] as bool? ?? true,
      );

  VisibilityKeyframe clone() => VisibilityKeyframe(time, visible);
}

class OpacityKeyframe {
  double time;
  double opacity;

  OpacityKeyframe(this.time, this.opacity);

  Map<String, dynamic> toJson() => {'time': time, 'opacity': opacity};

  factory OpacityKeyframe.fromJson(Map<String, dynamic> json) =>
      OpacityKeyframe(
        (json['time'] as num?)?.toDouble() ?? 0,
        (json['opacity'] as num?)?.toDouble() ?? 1.0,
      );

  OpacityKeyframe clone() => OpacityKeyframe(time, opacity);
}

class FigureColorKeyframe {
  double time;
  String color;

  FigureColorKeyframe(this.time, this.color);

  Map<String, dynamic> toJson() => {'time': time, 'color': color};

  factory FigureColorKeyframe.fromJson(Map<String, dynamic> json) =>
      FigureColorKeyframe(
        (json['time'] as num?)?.toDouble() ?? 0,
        json['color'] as String? ?? '#000000',
      );

  FigureColorKeyframe clone() => FigureColorKeyframe(time, color);
}

class SegmentImageKeyframe {
  double time;
  int imageIndex;

  SegmentImageKeyframe(this.time, this.imageIndex);

  Map<String, dynamic> toJson() => {'time': time, 'imageIndex': imageIndex};

  factory SegmentImageKeyframe.fromJson(Map<String, dynamic> json) =>
      SegmentImageKeyframe(
        (json['time'] as num?)?.toDouble() ?? 0,
        (json['imageIndex'] as num?)?.toInt() ?? 0,
      );

  SegmentImageKeyframe clone() => SegmentImageKeyframe(time, imageIndex);
}

/// A structural layer group (folder) that owns a set of segments. Segments
/// not listed in any group belong to the implicit default group.
class LayerGroup {
  String id;
  String name;
  List<String> segmentIds;
  bool visible;
  bool locked;

  LayerGroup({
    String? id,
    this.name = 'Group',
    List<String>? segmentIds,
    this.visible = true,
    this.locked = false,
  })  : id = id ?? 'layer_${LayerGroup._gid()}',
        segmentIds = segmentIds ?? [];

  static int _gcounter = 0;
  static int _gid() {
    _gcounter++;
    return DateTime.now().microsecondsSinceEpoch & 0xFFFFF |
        (_gcounter << 20);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'segmentIds': segmentIds,
        'visible': visible,
        'locked': locked,
      };

  factory LayerGroup.fromJson(Map<String, dynamic> json) => LayerGroup(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Default',
        segmentIds: (json['segmentIds'] as List?)
            ?.whereType<String>()
            .toList(),
        visible: json['visible'] as bool? ?? true,
        locked: json['locked'] as bool? ?? false,
      );

  LayerGroup clone() => LayerGroup(
        id: id,
        name: name,
        segmentIds: List.of(segmentIds),
        visible: visible,
        locked: locked,
      );
}

/// The whole drawing: a set of points + segments + animation metadata.
///
/// Mirrors `src/core/nodes/Figure.js` (id-animate-nodes) for JSON
/// compatibility.
class Figure {
  String name;
  List<Point2> points;
  List<Segment> segments;
  List<dynamic> animations;
  double canvasWidth;
  double canvasHeight;
  double fps;
  String canvasColor;
  Map<String, CycleFill> cycleFills; // key "p1,p2,p3"
  List<int> rootIndices;
  Map<String, List<VisibilityKeyframe>> visibility;
  Map<String, List<OpacityKeyframe>> opacity;
  Map<String, List<FigureColorKeyframe>> colors;
  Map<String, List<SegmentImageKeyframe>> segmentImages;

  /// Segment ids that were explicitly attached at a host joint point.
  ///
  /// `figureKeyFor` treats every point beyond an `isAttached` joint as part of
  /// the attached figure. That is not enough to detach safely: a pre-existing
  /// child of the host can share the same joint and would otherwise be pulled
  /// away together with the newly attached object. Recording the dragged
  /// segments at attach time keeps detach scoped to exactly that object.
  Map<int, List<String>> attachedSegments;

  /// Per-frame overrides for properties that have no dedicated keyframe track
  /// (curve handles, stroke width, image transform, text, per-segment
  /// hidden/colour/layer...). Key: rounded frame -> `seg:<id>:<property>`.
  final Map<double, Map<String, dynamic>> frameOverrides;

  Map<String, bool> figureCollision; // per-figure game-dev flag, key = figureKeyFor(root)
  List<LayerGroup> groups;

  static const String defaultGroupId = 'layer_default';

  Figure([this.name = 'Figure'])
      : points = [],
        segments = [],
        animations = [],
        canvasWidth = 1280,
        canvasHeight = 720,
        fps = 12,
        canvasColor = '#ffffff',
        cycleFills = {},
        rootIndices = [],
        visibility = {},
        opacity = {},
        colors = {},
        segmentImages = {},
        attachedSegments = {},
        frameOverrides = {},
        figureCollision = {},
        groups = [LayerGroup(id: defaultGroupId, name: 'Default')];

  int addPoint(double x, double y) {
    final index = points.length;
    points.add(Point2(x, y));
    return index;
  }

  Point2? removePoint(int index) {
    final segsUsing = segments.where(
      (s) => s.point1Index == index || s.point2Index == index,
    );
    if (segsUsing.isNotEmpty && points.length <= 2) return null;
    for (final s in segsUsing) {
      if (s.point1Index == index) s.point1Index = 0;
      if (s.point2Index == index) s.point2Index = 0;
    }
    final removed = points[index];
    for (final s in segments) {
      if (s.point1Index > index) s.point1Index--;
      if (s.point2Index > index) s.point2Index--;
    }
    points.removeAt(index);
    return removed;
  }

  Segment addSegment([String type = 'line']) {
    final p1 = addPoint(0, 0);
    final p2 = addPoint(100, 0);
    return createSegment(type, p1, p2);
  }

  Segment createSegment(String type, int p1Idx, int p2Idx) {
    final seg = Segment(type)
      ..point1Index = p1Idx
      ..point2Index = p2Idx
      ..layer = segments.length;
    segments.add(seg);
    ensureDefaultGroup();
    if (!groups.first.segmentIds.contains(seg.id)) {
      groups.first.segmentIds.add(seg.id);
    }
    return seg;
  }

  /// Ensures every segment in [segments] belongs to a group. Used after JSON
  /// deserialisation or SVG import where segments may have been inserted
  /// directly rather than through [createSegment]. Ungrouped segments are
  /// appended to the default group; stale ids are pruned.
  void ensureSegmentsInDefaultGroup() {
    ensureDefaultGroup();
    final ids = {for (final s in segments) s.id};
    for (final g in groups) {
      g.segmentIds.removeWhere((id) => !ids.contains(id));
    }
    final defaultGroup = groups.firstWhere((g) => g.id == defaultGroupId);
    for (final s in segments) {
      if (!defaultGroup.segmentIds.contains(s.id)) {
        defaultGroup.segmentIds.add(s.id);
      }
    }
  }

  Segment? removeSegment(String segId) {
    final idx = segments.indexWhere((s) => s.id == segId);
    if (idx == -1) return null;
    final seg = segments.removeAt(idx);
    for (final g in groups) {
      g.segmentIds.remove(segId);
    }
    for (final joint in attachedSegments.keys.toList()) {
      attachedSegments[joint]?.remove(segId);
      if (attachedSegments[joint]?.isEmpty ?? true) {
        attachedSegments.remove(joint);
      }
    }
    repairRoots();
    return seg;
  }

  /// Descendants of [pivotIdx] in the root-based hierarchy. Parent of each
  /// point is the first connected point discovered by a BFS seeded from
  /// [rootIndices]. Returns points whose ancestor chain passes through
  /// [pivotIdx] (excluding the pivot itself).
  List<int> childPoints(int pivotIdx) {
    final roots = rootIndices.isNotEmpty ? rootIndices : [0];
    final parent = <int, int>{};
    final visited = <int>{};
    final queue = <int>[];
    for (final r in roots) {
      if (r >= 0 && r < points.length && !visited.contains(r)) {
        visited.add(r);
        queue.add(r);
      }
    }
    var qi = 0;
    while (qi < queue.length) {
      final idx = queue[qi++];
      for (final s in segments) {
        final other = s.point1Index == idx
            ? s.point2Index
            : s.point2Index == idx
                ? s.point1Index
                : -1;
        if (other >= 0 && other < points.length && !visited.contains(other)) {
          visited.add(other);
          parent[other] = idx;
          queue.add(other);
        }
      }
    }
    final result = <int>[];
    for (final n in visited) {
      var cur = n;
      while (parent.containsKey(cur)) {
        if (parent[cur] == pivotIdx) {
          result.add(n);
          break;
        }
        cur = parent[cur]!;
      }
    }
    return result;
  }

  Segment? getSegment(String segId) {
    for (final s in segments) {
      if (s.id == segId) return s;
    }
    return null;
  }

  List<int> getFigureRoots() =>
      (rootIndices.isNotEmpty) ? List.of(rootIndices) : [0];

  /// Stable per-figure key for [pointIdx] inside a merged (attached) figure.
  ///
  /// A merged component normally has a single root, so figure-wide overrides
  /// (color/visibility/opacity) would bleed from the root figure into any
  /// attached figure. Points that are marked `isAttached` are treated as the
  /// joints that separate figures: the side beyond such a joint gets its own
  /// key (the joint point index) so overrides stay scoped to one figure.
  int figureKeyFor(int pointIdx) {
    if (pointIdx < 0 || pointIdx >= points.length) return 0;
    final roots = getFigureRoots();
    if (roots.isEmpty) return 0;
    final map = <int, int>{};
    for (final r in roots) {
      if (map.containsKey(r)) continue;
      final stack = <int>[r];
      map[r] = r;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        for (final s in segments) {
          final other = s.point1Index == cur
              ? s.point2Index
              : s.point2Index == cur
                  ? s.point1Index
                  : -1;
          if (other < 0 || other >= points.length) continue;
          if (map.containsKey(other)) continue;
          // The neighbour beyond an attached joint starts its own figure.
          map[other] = points[cur].isAttached ? cur : map[cur]!;
          stack.add(other);
        }
      }
    }
    return map[pointIdx] ?? roots.first;
  }

  /// Stable per-figure key for a [seg]. At a joint boundary the two endpoints
  /// map to different keys (the joint itself maps to the host figure); a
  /// segment that spans two figures belongs to the side whose endpoint is NOT
  /// the attached joint, so overrides apply to the correct figure regardless
  /// of which endpoint is `point1`.
  int segmentFigureKey(Segment seg) {
    final k1 = figureKeyFor(seg.point1Index);
    final k2 = figureKeyFor(seg.point2Index);
    if (k1 == k2) return k1;
    final a = points[seg.point1Index].isAttached;
    final b = points[seg.point2Index].isAttached;
    if (a && !b) return k2;
    if (b && !a) return k1;
    return k1;
  }

  double? _nextAuthoredAfter(double time, Set<double> authoredTimes) {
    final frame = time.roundToDouble();
    double? next;
    for (final t in authoredTimes) {
      final rt = t.roundToDouble();
      if (rt > frame && (next == null || rt < next)) next = rt;
    }
    return next;
  }

  void setFigureVisibility(
    int root,
    double time,
    bool visible, {
    Set<double>? authoredTimes,
  }) {
    final key = root.toString();
    final track = visibility.putIfAbsent(key, () => []);
    if (authoredTimes != null) {
      final next = _nextAuthoredAfter(time, authoredTimes);
      if (next != null) {
        if (!track.any((kf) => (kf.time - next).abs() < 0.001)) {
          track.add(VisibilityKeyframe(next, getFigureVisibility(root, next)));
        }
        final t1 = time.roundToDouble() + 1;
        if (t1 < next &&
            !track.any((kf) => (kf.time - t1).abs() < 0.001)) {
          track.add(VisibilityKeyframe(t1, getFigureVisibility(root, t1)));
        }
        track.sort((a, b) => a.time.compareTo(b.time));
      }
    }
    final existing =
        track.where((kf) => (kf.time - time).abs() < 0.001).toList();
    if (existing.isNotEmpty) {
      existing.first.visible = visible;
    } else {
      track.add(VisibilityKeyframe(time, visible));
      track.sort((a, b) => a.time.compareTo(b.time));
    }
  }

  bool getFigureVisibility(int root, double time) {
    final track = visibility[root.toString()] ?? [];
    var visible = true;
    for (final kf in track) {
      if (kf.time <= time + 0.0001) visible = kf.visible;
    }
    return visible;
  }

  List<VisibilityKeyframe> getFigureVisibilityKeyframes(int root) =>
      visibility[root.toString()] ?? [];

  /// Game-dev collision flag for the whole figure identified by [root].
  bool getFigureCollision(int root) => figureCollision[root.toString()] ?? false;

  void setFigureCollision(int root, bool value) {
    final key = root.toString();
    if (value) {
      figureCollision[key] = true;
    } else {
      figureCollision.remove(key);
    }
  }

  void setFigureOpacity(
    int root,
    double time,
    double val, {
    Set<double>? authoredTimes,
  }) {
    final key = root.toString();
    final track = opacity.putIfAbsent(key, () => []);
    if (authoredTimes != null) {
      final next = _nextAuthoredAfter(time, authoredTimes);
      if (next != null) {
        if (!track.any((kf) => (kf.time - next).abs() < 0.001)) {
          track.add(OpacityKeyframe(next, getFigureOpacity(root, next)));
        }
        final t1 = time.roundToDouble() + 1;
        if (t1 < next &&
            !track.any((kf) => (kf.time - t1).abs() < 0.001)) {
          track.add(OpacityKeyframe(t1, getFigureOpacity(root, t1)));
        }
        track.sort((a, b) => a.time.compareTo(b.time));
      }
    }
    final existing =
        track.where((kf) => (kf.time - time).abs() < 0.001).toList();
    if (existing.isNotEmpty) {
      existing.first.opacity = val;
    } else {
      track.add(OpacityKeyframe(time, val));
      track.sort((a, b) => a.time.compareTo(b.time));
    }
  }

  double getFigureOpacity(int root, double time) {
    final track = opacity[root.toString()] ?? [];
    var val = 1.0;
    for (final kf in track) {
      if (kf.time <= time + 0.0001) val = kf.opacity;
    }
    return val;
  }

  List<OpacityKeyframe> getFigureOpacityKeyframes(int root) =>
      opacity[root.toString()] ?? [];

  void setFigureColorOverride(
    int root,
    double time,
    String color, {
    Set<double>? authoredTimes,
  }) {
    final key = root.toString();
    final track = colors.putIfAbsent(key, () => []);
    if (authoredTimes != null) {
      final next = _nextAuthoredAfter(time, authoredTimes);
      if (next != null) {
        if (!track.any((kf) => (kf.time - next).abs() < 0.001)) {
          final current = getFigureColorOverride(root, next);
          if (current != null) {
            track.add(FigureColorKeyframe(next, current));
          }
        }
        final t1 = time.roundToDouble() + 1;
        if (t1 < next &&
            !track.any((kf) => (kf.time - t1).abs() < 0.001)) {
          final current1 = getFigureColorOverride(root, t1);
          if (current1 != null) {
            track.add(FigureColorKeyframe(t1, current1));
          }
        }
        track.sort((a, b) => a.time.compareTo(b.time));
      }
    }
    final existing =
        track.where((kf) => (kf.time - time).abs() < 0.001).toList();
    if (existing.isNotEmpty) {
      existing.first.color = color;
    } else {
      track.add(FigureColorKeyframe(time, color));
      track.sort((a, b) => a.time.compareTo(b.time));
    }
  }

  String? getFigureColorOverride(int root, double time) {
    final track = colors[root.toString()];
    if (track == null || track.isEmpty) return null;
    var val = track.first.color;
    bool found = false;
    for (final kf in track) {
      if (kf.time <= time + 0.0001) {
        val = kf.color;
        found = true;
      }
    }
    return found ? val : null;
  }

  void removeFigureColorOverride(int root, double time) {
    final key = root.toString();
    final track = colors[key];
    if (track != null) {
      track.removeWhere((kf) => (kf.time - time).abs() < 0.001);
      if (track.isEmpty) colors.remove(key);
    }
  }

  void setSegmentImageIndex(
    String segId,
    double time,
    int imageIndex, {
    Set<double>? authoredTimes,
  }) {
    final track = segmentImages.putIfAbsent(segId, () => []);
    if (authoredTimes != null) {
      final next = _nextAuthoredAfter(time, authoredTimes);
      if (next != null) {
        if (!track.any((kf) => (kf.time - next).abs() < 0.001)) {
          final current = getSegmentImageIndex(segId, next);
          if (current != null) {
            track.add(SegmentImageKeyframe(next, current));
          }
        }
        final t1 = time.roundToDouble() + 1;
        if (t1 < next &&
            !track.any((kf) => (kf.time - t1).abs() < 0.001)) {
          final current1 = getSegmentImageIndex(segId, t1);
          if (current1 != null) {
            track.add(SegmentImageKeyframe(t1, current1));
          }
        }
        track.sort((a, b) => a.time.compareTo(b.time));
      }
    }
    final existing =
        track.where((kf) => (kf.time - time).abs() < 0.001).toList();
    if (existing.isNotEmpty) {
      existing.first.imageIndex = imageIndex;
    } else {
      track.add(SegmentImageKeyframe(time, imageIndex));
      track.sort((a, b) => a.time.compareTo(b.time));
    }
  }

  int? getSegmentImageIndex(String segId, double time) {
    final track = segmentImages[segId];
    if (track == null || track.isEmpty) return null;
    var val = track.first.imageIndex;
    bool found = false;
    for (final kf in track) {
      if (kf.time <= time + 0.0001) {
        val = kf.imageIndex;
        found = true;
      }
    }
    return found ? val : null;
  }

  // ---------------------------------------------------------------------------
  // Generic per-frame overrides
  // ---------------------------------------------------------------------------

  /// All frame times that contain any authored keyframe/override in this
  /// figure. Point-track times live in [FigureAnimation] and must be merged by
  /// the caller when protecting boundaries across systems.
  Set<double> authoredFrameTimes() {
    final times = <double>{...frameOverrides.keys};
    for (final track in visibility.values) {
      for (final kf in track) {
        times.add(kf.time.roundToDouble());
      }
    }
    for (final track in opacity.values) {
      for (final kf in track) {
        times.add(kf.time.roundToDouble());
      }
    }
    for (final track in colors.values) {
      for (final kf in track) {
        times.add(kf.time.roundToDouble());
      }
    }
    for (final track in segmentImages.values) {
      for (final kf in track) {
        times.add(kf.time.roundToDouble());
      }
    }
    return times;
  }

  /// Records [value] as the value of [key] at [time]. Later frames keep this
  /// value until another override is written (hold semantics).
  void setFrameOverride(String key, dynamic value, double time) {
    final frame = time.roundToDouble();
    frameOverrides.putIfAbsent(frame, () => <String, dynamic>{})[key] = value;
  }

  /// If an authored frame exists after [time] and has no explicit override for
  /// [key], pin the value it currently resolves to so editing [time] does not
  /// leak forward into already-authored frames. Also pins [time]+1 when there
  /// is a gap, so un-authored in-between frames keep their old value.
  void protectNextOverrideBoundary(
    String key,
    double time,
    dynamic fallback,
    Set<double> authoredTimes,
  ) {
    final frame = time.roundToDouble();
    double? next;
    for (final t in authoredTimes) {
      final rt = t.roundToDouble();
      if (rt > frame && (next == null || rt < next)) next = rt;
    }
    if (next == null) return;

    void pin(double target) {
      final frameMap = frameOverrides[target];
      if (frameMap != null && frameMap.containsKey(key)) return;
      final resolved = frameObject(key, target, fallback);
      frameOverrides.putIfAbsent(target, () => <String, dynamic>{})[key] =
          resolved;
    }

    pin(next);
    final t1 = frame + 1;
    if (t1 < next) pin(t1);
  }

  /// Seeds frame 0 with [value] when [key] has no earlier override. Call this
  /// with the property's current value BEFORE a tool mutates it, so scrubbing
  /// back to earlier frames still shows the original state.
  void captureFrameOverride(String key, dynamic value) {
    frameOverrides
        .putIfAbsent(0.0, () => <String, dynamic>{})
        .putIfAbsent(key, () => value);
  }

  static final Object _noFrameOverride = Object();

  /// Raw override at or before [time]. [_noFrameOverride] means "not set",
  /// which lets nullable values (e.g. `text = null`) be stored correctly.
  Object? _frameRaw(String key, double time) {
    double? best;
    for (final t in frameOverrides.keys) {
      if (t <= time + 0.0001 && (best == null || t > best)) best = t;
    }
    if (best == null) return _noFrameOverride;
    final frame = frameOverrides[best]!;
    if (!frame.containsKey(key)) return _noFrameOverride;
    return frame[key];
  }

  bool hasFrameOverride(String key, double time) =>
      !identical(_frameRaw(key, time), _noFrameOverride);

  /// Latest override for [key] at or before [time], or null when none exists.
  T? frameValue<T>(String key, double time) {
    final raw = _frameRaw(key, time);
    if (identical(raw, _noFrameOverride)) return null;
    return raw is T ? raw : null;
  }

  /// Override of any type (numbers, strings, bools, `auto` dimensions...).
  dynamic frameObject(String key, double time, dynamic fallback) {
    final raw = _frameRaw(key, time);
    return identical(raw, _noFrameOverride) ? fallback : raw;
  }

  double frameDouble(String key, double time, double fallback) =>
      frameValue<num>(key, time)?.toDouble() ?? fallback;

  int frameInt(String key, double time, int fallback) =>
      frameValue<num>(key, time)?.round() ?? fallback;

  bool frameBool(String key, double time, bool fallback) =>
      frameValue<bool>(key, time) ?? fallback;

  String frameString(String key, double time, String fallback) =>
      frameValue<String>(key, time) ?? fallback;

  String? frameNullableString(String key, double time, String? fallback) {
    final raw = _frameRaw(key, time);
    if (identical(raw, _noFrameOverride)) return fallback;
    return raw is String ? raw : null;
  }

  double? frameNullableDouble(String key, double time, double? fallback) {
    final raw = _frameRaw(key, time);
    if (identical(raw, _noFrameOverride)) return fallback;
    return raw is num ? raw.toDouble() : null;
  }

  /// Resolves every visual property of [seg] at [time].
  SegmentFrameStyle styleFor(Segment seg, double time, {bool enabled = true}) =>
      SegmentFrameStyle(this, seg, time, enabled: enabled);

  /// Returns the connected set of point indices containing [rootIndex].
  Set<int> connectedComponent(int rootIndex) {
    final comp = <int>{rootIndex};
    final queue = <int>[rootIndex];
    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      for (final s in segments) {
        final other = s.point1Index == idx
            ? s.point2Index
            : s.point2Index == idx
                ? s.point1Index
                : -1;
        if (other >= 0 && !comp.contains(other)) {
          comp.add(other);
          queue.add(other);
        }
      }
    }
    return comp;
  }

  /// Recomputes [rootIndices] so that every segment-connected component of
  /// points has EXACTLY one root. A component that ends up root-less (e.g.
  /// after a segment delete or split detaches a part) gains the lowest point
  /// of its component as a new root; a component that gained extra roots
  /// (e.g. from a merge) keeps only the lowest of its existing roots.
  void repairRoots() {
    if (points.isEmpty) {
      rootIndices = [];
      return;
    }
    final visited = <int>{};
    final newRoots = <int>[];
    for (var start = 0; start < points.length; start++) {
      if (visited.contains(start)) continue;
      final comp = connectedComponent(start);
      visited.addAll(comp);
      final existing = rootIndices.where(comp.contains).toList();
      if (existing.isNotEmpty) {
        newRoots.add(existing.reduce((a, b) => a < b ? a : b));
      } else {
        final root = comp.reduce((a, b) => a < b ? a : b);
        if (root >= 0 && root < points.length) {
          newRoots.add(root);
        }
      }
    }
    newRoots.removeWhere((r) => r < 0 || r >= points.length);
    rootIndices = newRoots..sort();
  }

  /// Removes the connected sub-figure containing [root] and returns the
  /// removed point indices (descending order), or null when invalid.
  List<int>? removeFigure(int root) {
    if (root < 0 || root >= points.length) return null;
    final comp = connectedComponent(root);
    segments.removeWhere(
      (s) => comp.contains(s.point1Index) && comp.contains(s.point2Index),
    );
    for (final g in groups) {
      final validIds = segments.map((s) => s.id).toSet();
      g.segmentIds.removeWhere((id) => !validIds.contains(id));
    }
    final removed = comp.toList()..sort((a, b) => b - a);
    final removedSet = comp;
    int remap(int i) {
      var n = i;
      for (final r in removed) {
        if (r < n) n--;
      }
      return n;
    }

    for (final r in removed) {
      points.removeAt(r);
    }
    for (final s in segments) {
      s.point1Index = remap(s.point1Index);
      s.point2Index = remap(s.point2Index);
    }
    rootIndices = rootIndices
        .where((r) => !removedSet.contains(r))
        .map(remap)
        .toList();
    if (rootIndices.isEmpty) rootIndices = [0];
    if (visibility.isNotEmpty) {
      final newVis = <String, List<VisibilityKeyframe>>{};
      visibility.forEach((k, v) {
        final rk = int.tryParse(k);
        if (rk == null || removedSet.contains(rk)) return;
        newVis[remap(rk).toString()] = v;
      });
      visibility = newVis;
    }
    if (opacity.isNotEmpty) {
      final newOp = <String, List<OpacityKeyframe>>{};
      opacity.forEach((k, v) {
        final rk = int.tryParse(k);
        if (rk == null || removedSet.contains(rk)) return;
        newOp[remap(rk).toString()] = v;
      });
      opacity = newOp;
    }
    if (cycleFills.isNotEmpty) {
      final newCF = <String, CycleFill>{};
      cycleFills.forEach((key, entry) {
        final parts = key.split(',').map(int.parse).toList();
        if (parts.any(removedSet.contains)) return;
        newCF[parts.map(remap).join(',')] = entry;
      });
      cycleFills = newCF;
    }
    if (figureCollision.isNotEmpty) {
      final newFC = <String, bool>{};
      figureCollision.forEach((k, v) {
        final rk = int.tryParse(k);
        if (rk == null || removedSet.contains(rk)) return;
        newFC[remap(rk).toString()] = v;
      });
      figureCollision = newFC;
    }
    if (attachedSegments.isNotEmpty) {
      final newAttached = <int, List<String>>{};
      attachedSegments.forEach((joint, ids) {
        if (removedSet.contains(joint)) return;
        newAttached[remap(joint)] = ids;
      });
      attachedSegments = newAttached;
    }
    return removed;
  }

  /// Merges [movedIdx] into [targetIdx]: every segment that referenced
  /// [movedIdx] now references [targetIdx], then the moved point is removed
  /// and indices remapped. The moved point's root (and any root of the dragged
  /// figure) is dropped so only the target's root survives. Returns the
  /// (remapped) surviving point index.
  int joinPoints(int movedIdx, int targetIdx) {
    if (movedIdx == targetIdx) return targetIdx;
    if (movedIdx < 0 || movedIdx >= points.length) return targetIdx;
    if (targetIdx < 0 || targetIdx >= points.length) return targetIdx;
    final movedComp = connectedComponent(movedIdx);
    final sameFigure = movedComp.contains(targetIdx);
    final movedFigureRoot = rootIndices.firstWhere(
      movedComp.contains,
      orElse: () => movedIdx,
    );
    for (final s in segments) {
      if (s.point1Index == movedIdx) s.point1Index = targetIdx;
      if (s.point2Index == movedIdx) s.point2Index = targetIdx;
    }
    rootIndices.remove(movedIdx);
    rootIndices = rootIndices.map((r) => r > movedIdx ? r - 1 : r).toList();
    points.removeAt(movedIdx);
    final newTarget = targetIdx > movedIdx ? targetIdx - 1 : targetIdx;
    for (final s in segments) {
      if (s.point1Index > movedIdx) s.point1Index--;
      if (s.point2Index > movedIdx) s.point2Index--;
    }
    if (!sameFigure) {
      final remappedRoot = movedFigureRoot > movedIdx
          ? movedFigureRoot - 1
          : movedFigureRoot;
      rootIndices.remove(remappedRoot);
    }
    // Attachment joints are stored by point index, so they must follow the
    // same renumbering as the points when the dragged point is removed.
    if (attachedSegments.isNotEmpty) {
      final remapped = <int, List<String>>{};
      attachedSegments.forEach((joint, ids) {
        final newJoint = joint == movedIdx
            ? newTarget
            : joint > movedIdx
                ? joint - 1
                : joint;
        remapped[newJoint] = ids;
      });
      attachedSegments = remapped;
    }
    // Re-key figure-scoped overrides: keys that reference a point inside the
    // moved component follow that figure to its new per-figure key (so colour,
    // visibility, opacity and collision survive attach/join). The dragged point
    // itself ([movedIdx]) is removed, but overrides keyed to it must follow the
    // moved figure too (this is the root pivot of an attached figure). Keys of
    // other figures are just renumbered past the removed point.
    String? joinKey(String k) {
      final rk = int.tryParse(k);
      if (rk == null) return null;
      if (movedComp.contains(rk)) {
        if (rk != movedIdx) {
          final renum = rk > movedIdx ? rk - 1 : rk;
          if (renum < 0 || renum >= points.length) return null;
          final fk = figureKeyFor(renum);
          if (fk < 0) return null;
          return fk.toString();
        }
        // rk == movedIdx: the dragged (removed) point. Resolve the moved
        // figure's new key via any surviving point of the moved component.
        for (final p in movedComp) {
          if (p == movedIdx) continue;
          final renum = p > movedIdx ? p - 1 : p;
          if (renum >= 0 && renum < points.length) {
            final fk = figureKeyFor(renum);
            if (fk >= 0) return fk.toString();
          }
        }
        return null;
      }
      final renum = rk > movedIdx ? rk - 1 : rk;
      if (renum < 0 || renum >= points.length) return null;
      return renum.toString();
    }

    _rekeyFigureOverrides(joinKey);
    if (cycleFills.isNotEmpty) {
      final newCF = <String, CycleFill>{};
      cycleFills.forEach((key, entry) {
        final parts = key.split(',').map(int.parse).toList();
        if (parts.any((p) => p == movedIdx)) return;
        newCF[parts.map((p) => p > movedIdx ? p - 1 : p).join(',')] = entry;
      });
      cycleFills = newCF;
    }
    repairRoots();
    return newTarget;
  }

  /// Re-keys every figure-scoped override map ([colors], [visibility],
  /// [opacity], [figureCollision]) using [newKeyFor]; entries whose key
  /// resolves to null are dropped.
  void _rekeyFigureOverrides(String? Function(String key) newKeyFor) {
    if (visibility.isNotEmpty) {
      final newVis = <String, List<VisibilityKeyframe>>{};
      visibility.forEach((k, v) {
        final nk = newKeyFor(k);
        if (nk == null) return;
        newVis.putIfAbsent(nk, () => []).addAll(v);
      });
      visibility = newVis;
    }
    if (opacity.isNotEmpty) {
      final newOp = <String, List<OpacityKeyframe>>{};
      opacity.forEach((k, v) {
        final nk = newKeyFor(k);
        if (nk == null) return;
        newOp.putIfAbsent(nk, () => []).addAll(v);
      });
      opacity = newOp;
    }
    if (colors.isNotEmpty) {
      final newColors = <String, List<FigureColorKeyframe>>{};
      colors.forEach((k, v) {
        final nk = newKeyFor(k);
        if (nk == null) return;
        newColors.putIfAbsent(nk, () => []).addAll(v);
      });
      colors = newColors;
    }
    if (figureCollision.isNotEmpty) {
      final newFC = <String, bool>{};
      figureCollision.forEach((k, v) {
        final nk = newKeyFor(k);
        if (nk == null) return;
        newFC[nk] = v;
      });
      figureCollision = newFC;
    }
  }

  /// Moves every figure-scoped override from [fromKey] to [toKey] (other keys
  /// keep their values). Used when a figure gains a new root (e.g. detaching
  /// an attached figure) so colour/visibility/opacity/collision survive.
  void moveFigureOverrides(int fromKey, int toKey) {
    _rekeyFigureOverrides((k) {
      final rk = int.tryParse(k);
      if (rk == null) return null;
      return rk == fromKey ? toKey.toString() : k;
    });
  }

  /// Remembers which segments belong to the figure being attached at [jointIdx].
  void setAttachedSegments(int jointIdx, Iterable<String> segmentIds) {
    final ids = segmentIds.toSet().toList();
    if (ids.isEmpty) {
      attachedSegments.remove(jointIdx);
    } else {
      attachedSegments[jointIdx] = ids;
    }
  }

  /// Detaches exactly the object recorded at [jointIdx].
  ///
  /// Returns the new root created for the detached object plus the points and
  /// segments that moved with it. A host child that merely shares the joint is
  /// not included because its segment id was never recorded as attached.
  ({int newRoot, Set<int> pointIndices, Set<String> segmentIds})?
      detachAttachedAt(int jointIdx) {
    final directIds = attachedSegments[jointIdx]?.toSet() ?? <String>{};
    if (directIds.isEmpty ||
        jointIdx < 0 ||
        jointIdx >= points.length) {
      return null;
    }

    // Include figures attached further down the detached object's tree.
    final allIds = <String>{...directIds};
    final nestedKeys = <int>{jointIdx};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in attachedSegments.entries) {
        if (!nestedKeys.contains(entry.key)) continue;
        for (final id in entry.value) {
          if (allIds.add(id)) changed = true;
        }
      }
      final touched = <int>{};
      for (final s in segments) {
        if (!allIds.contains(s.id)) continue;
        touched.add(s.point1Index);
        touched.add(s.point2Index);
      }
      for (final key in attachedSegments.keys) {
        if (touched.contains(key) && nestedKeys.add(key)) changed = true;
      }
    }

    final attachSegs = segments.where((s) => allIds.contains(s.id)).toList();
    if (attachSegs.isEmpty) {
      attachedSegments.remove(jointIdx);
      return null;
    }
    final attachPts = <int>{};
    for (final s in attachSegs) {
      attachPts.add(s.point1Index);
      attachPts.add(s.point2Index);
    }
    attachPts.remove(jointIdx);
    if (attachPts.isEmpty) {
      attachedSegments.remove(jointIdx);
      return null;
    }

    final newRoot = addPoint(points[jointIdx].x, points[jointIdx].y);
    for (final s in segments) {
      if (!allIds.contains(s.id)) continue;
      if (s.point1Index == jointIdx) s.point1Index = newRoot;
      if (s.point2Index == jointIdx) s.point2Index = newRoot;
    }
    if (!rootIndices.contains(newRoot)) rootIndices.add(newRoot);
    repairRoots();
    points[jointIdx].isAttached = false;
    moveFigureOverrides(jointIdx, newRoot);
    attachedSegments.remove(jointIdx);

    return (
      newRoot: newRoot,
      pointIndices: attachPts,
      segmentIds: allIds,
    );
  }

  /// Returns a copy of [attachedSegments] with imported point/segment ids
  /// remapped, used when merging a saved figure that already has attachments.
  Map<int, List<String>> remappedAttachedSegments(
    Map<String, String> segIdMap,
    Map<int, int> pointIndexMap,
  ) {
    final mapped = <int, List<String>>{};
    attachedSegments.forEach((joint, ids) {
      final newJoint = pointIndexMap[joint] ?? joint;
      mapped[newJoint] = ids
          .map((id) => segIdMap[id] ?? id)
          .where((id) => id.isNotEmpty)
          .toList();
    });
    return mapped;
  }

  /// Splits a shared joint so [jointIdx] stops connecting to
  /// [detachFromIdx]. A new copy of the joint point is appended (placed at
  /// [copyX],[copyY]) and the segment that linked jointIdx→detachFromIdx is
  /// re-pointed to the new point, which becomes a new root. Returns the new
  /// point index, or -1 when there is no segment between the two points.
  int splitJoint(int jointIdx, int detachFromIdx, double copyX, double copyY) {
    if (jointIdx < 0 ||
        jointIdx >= points.length ||
        detachFromIdx < 0 ||
        detachFromIdx >= points.length) {
      return -1;
    }
    final segIdx = segments.indexWhere((s) =>
        (s.point1Index == jointIdx && s.point2Index == detachFromIdx) ||
        (s.point1Index == detachFromIdx && s.point2Index == jointIdx));
    if (segIdx == -1) return -1;
    // Remember the figure keys on both sides of the joint BEFORE splitting so
    // overrides can follow the detached side to its new root.
    final detachKey = figureKeyFor(detachFromIdx);
    final jointKey = figureKeyFor(jointIdx);
    final newIdx = addPoint(copyX, copyY);
    final seg = segments[segIdx];
    if (seg.point1Index == jointIdx) {
      seg.point1Index = newIdx;
    } else {
      seg.point2Index = newIdx;
    }
    if (!rootIndices.contains(newIdx)) rootIndices.add(newIdx);
    repairRoots();
    // Only when the joint separated two figures does the detached side get its
    // own figure key (newIdx); then its overrides move from the old key.
    if (detachKey != jointKey && detachKey >= 0 && detachKey < points.length) {
      _rekeyFigureOverrides((k) {
        final rk = int.tryParse(k);
        if (rk == null) return null;
        return rk == detachKey ? newIdx.toString() : k;
      });
    }
    return newIdx;
  }

  /// Id of the group that owns [segId], or [defaultGroupId] when unassigned.
  String groupOf(String segId) {
    for (final g in groups) {
      if (g.segmentIds.contains(segId)) return g.id;
    }
    return defaultGroupId;
  }

  /// Ensures [defaultGroupId] exists (always kept, even when empty).
  void ensureDefaultGroup() {
    if (!groups.any((g) => g.id == defaultGroupId)) {
      groups.insert(0, LayerGroup(id: defaultGroupId, name: 'Default'));
    }
  }

  /// Moves [segId] into the group with [groupId], removing it from any other
  /// group. Missing segment ids are pruned from all groups. Returns true when
  /// the target group existed (otherwise falls back to the default group).
  bool moveSegmentToGroup(String segId, String groupId) {
    for (final g in groups) {
      g.segmentIds.remove(segId);
    }
    final target = groups.where((g) => g.id == groupId).firstOrNull;
    if (target == null) {
      ensureDefaultGroup();
      final def = groups.firstWhere((g) => g.id == defaultGroupId);
      if (!def.segmentIds.contains(segId)) def.segmentIds.add(segId);
      return false;
    }
    if (!target.segmentIds.contains(segId)) target.segmentIds.add(segId);
    return true;
  }

  /// Moves [segId] into [groupId] and places it at [index] within that group's
  /// list. If the segment stays in the same group this acts as a reorder.
  /// After reordering, [Segment.layer] values inside the group are normalised
  /// to index order so that draw order matches the group list.
  void placeSegmentInGroup(String segId, String groupId, int index) {
    moveSegmentToGroup(segId, groupId);
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) return;
    group.segmentIds.remove(segId);
    group.segmentIds.insert(index.clamp(0, group.segmentIds.length), segId);
    _normalizeGroupLayer(group);
  }

  /// Normalises the `layer` of every segment inside a group to match its
  /// position in the group's [LayerGroup.segmentIds] (so draw order == list).
  void _normalizeGroupLayer(LayerGroup group) {
    for (var i = 0; i < group.segmentIds.length; i++) {
      final seg = getSegment(group.segmentIds[i]);
      if (seg != null) seg.layer = i;
    }
  }

  /// Reorders the segments within [groupId] to match [orderedIds]. Ids not
  /// present are ignored; segments already in the group not listed keep their
  /// relative order after the listed ones.
  void reorderSegmentsInGroup(String groupId, List<String> orderedIds) {
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) return;
    final present = orderedIds.where(group.segmentIds.contains).toList();
    final leftovers = group.segmentIds
        .where((id) => !present.contains(id))
        .toList();
    group.segmentIds
      ..clear()
      ..addAll([...present, ...leftovers]);
    _normalizeGroupLayer(group);
  }

  /// Reorders the groups. [oldIndex] and [newIndex] are indices into the
  /// `groups` list (which equals [orderedGroups] order). The default group can
  /// be moved anywhere; it is never removed.
  void reorderGroups(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= groups.length) return;
    final moved = groups.removeAt(oldIndex);
    groups.insert(newIndex.clamp(0, groups.length), moved);
    ensureDefaultGroup();
  }

  /// Groups in draw order (top first): follows the `groups` list order, so the
  /// default group can sit anywhere (including pinned to the bottom if it is
  /// last). Segments that also belong to a non-default group are pruned from
  /// the default group so each segment appears in exactly one group.
  List<LayerGroup> orderedGroups() {
    ensureDefaultGroup();
    final defaultGroup = groups.firstWhere((g) => g.id == defaultGroupId);
    defaultGroup.segmentIds.removeWhere(
      (s) => groups.any((g) => g.id != defaultGroupId && g.segmentIds.contains(s)),
    );
    return groups;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'timeUnit': 'frame',
        'points': points.map((p) => p.toJson()).toList(),
        'segments': segments.map((s) => s.toJson()).toList(),
        'animations': animations,
        'canvasWidth': canvasWidth,
        'canvasHeight': canvasHeight,
        'fps': fps,
        'canvasColor': canvasColor,
        'cycleFills': cycleFills.map((k, v) => MapEntry(k, v.toJson())),
        'rootIndices': rootIndices,
        'visibility': visibility.map(
            (k, v) => MapEntry(k, v.map((kf) => kf.toJson()).toList())),
        'opacity': opacity.map(
            (k, v) => MapEntry(k, v.map((kf) => kf.toJson()).toList())),
        'colors': colors.map(
            (k, v) => MapEntry(k, v.map((kf) => kf.toJson()).toList())),
        'segmentImages': segmentImages.map(
            (k, v) => MapEntry(k, v.map((kf) => kf.toJson()).toList())),
        'attachedSegments': attachedSegments.map(
            (k, v) => MapEntry(k.toString(), List<String>.from(v))),
        'frameOverrides': frameOverrides.map(
            (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v))),
        'figureCollision': figureCollision,
        'groups': groups.map((g) => g.toJson()).toList(),
      };

  /// Segments ordered for painting: group order first (the default group
  /// paints at the bottom, i.e. first), then each group's own [Segment.layer]
  /// order.
  List<Segment> segmentsInDrawOrder([double? time]) {
    final ordered = orderedGroups();
    final keyOf = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      keyOf[ordered[i].id] = i; // higher = on top (drawn later)
    }
    final sorted = [...segments]..sort((a, b) {
        final ka = keyOf[groupOf(a.id)] ?? 0;
        final kb = keyOf[groupOf(b.id)] ?? 0;
        if (ka != kb) return ka.compareTo(kb);
        final la = time == null ? a.layer : frameInt('seg:${a.id}:layer', time, a.layer);
        final lb = time == null ? b.layer : frameInt('seg:${b.id}:layer', time, b.layer);
        return la.compareTo(lb);
      });
    return sorted;
  }

  String exportToJson() => jsonEncodePretty(toJson());

  factory Figure.fromJson(Map<String, dynamic> data) {
    final fig = Figure(data['name'] as String? ?? 'Figure');
    final rawPoints = data['points'];
    if (rawPoints is List) {
      fig.points = rawPoints
          .whereType<Map<String, dynamic>>()
          .map((p) => Point2.fromJson(p))
          .toList();
    }
    if (fig.points.isEmpty && fig.segments.isNotEmpty) {
      fig.points = [Point2(0, 0)];
    }
    final rawSegs = data['segments'];
    if (rawSegs is List) {
      fig.segments = rawSegs
          .whereType<Map<String, dynamic>>()
          .map((s) => Segment.fromJson(s))
          .toList();
    }
    fig.animations = data['animations'] is List
        ? (data['animations'] as List).toList()
        : [];
    fig.canvasWidth = (data['canvasWidth'] as num?)?.toDouble() ?? 1280;
    fig.canvasHeight = (data['canvasHeight'] as num?)?.toDouble() ?? 720;
    fig.fps = (data['fps'] as num?)?.toDouble() ?? 12;
    final legacySeconds = data['timeUnit'] != 'frame' && fig.fps > 0;
    fig.canvasColor = data['canvasColor'] as String? ?? '#ffffff';

    final rawCF = data['cycleFills'];
    if (rawCF is Map) {
      rawCF.forEach((k, v) {
        if (v is Map) {
          fig.cycleFills[k.toString()] = CycleFill.fromJson(
            v.cast<String, dynamic>(),
          );
        }
      });
    }

    final rawRoots = data['rootIndices'];
    if (rawRoots is List) {
      fig.rootIndices = rawRoots
          .whereType<num>()
          .map((i) => i.toInt())
          .where((i) => i >= 0 && i < fig.points.length)
          .toList();
    }
    if (fig.rootIndices.isEmpty && fig.points.isNotEmpty) fig.rootIndices = [0];

    final rawVis = data['visibility'];
    if (rawVis is Map) {
      rawVis.forEach((k, v) {
        if (v is List) {
          fig.visibility[k.toString()] = v
              .whereType<Map>()
              .map((e) => VisibilityKeyframe.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }

    final rawOp = data['opacity'];
    if (rawOp is Map) {
      rawOp.forEach((k, v) {
        if (v is List) {
          fig.opacity[k.toString()] = v
              .whereType<Map>()
              .map((e) => OpacityKeyframe.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }

    final rawColors = data['colors'];
    if (rawColors is Map) {
      rawColors.forEach((k, v) {
        if (v is List) {
          fig.colors[k.toString()] = v
              .whereType<Map>()
              .map((e) => FigureColorKeyframe.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }

    final rawSegImgs = data['segmentImages'];
    if (rawSegImgs is Map) {
      rawSegImgs.forEach((k, v) {
        if (v is List) {
          fig.segmentImages[k.toString()] = v
              .whereType<Map>()
              .map((e) => SegmentImageKeyframe.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }

    final rawAttached = data['attachedSegments'];
    if (rawAttached is Map) {
      rawAttached.forEach((k, v) {
        final joint = int.tryParse(k.toString());
        if (joint == null || joint < 0 || joint >= fig.points.length) return;
        if (v is! List) return;
        final ids = v.whereType<String>().where((id) => id.isNotEmpty).toList();
        if (ids.isNotEmpty) fig.attachedSegments[joint] = ids;
      });
    }

    final rawOverrides = data['frameOverrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((k, v) {
        final frame = double.tryParse(k.toString());
        if (frame == null || v is! Map) return;
        fig.frameOverrides[frame] =
            v.map((key, value) => MapEntry(key.toString(), value));
      });
    }

    final rawGroups = data['groups'];
    if (rawGroups is List) {
      fig.groups = rawGroups
          .whereType<Map<String, dynamic>>()
          .map((g) => LayerGroup.fromJson(g))
          .toList();
    }

    final rawFigCollision = data['figureCollision'];
    if (rawFigCollision is Map) {
      rawFigCollision.forEach((k, v) {
        if (v is bool) fig.figureCollision[k.toString()] = v;
      });
    }
    if (legacySeconds) {
      // Pre-frame-unit save: keyframe times were stored in seconds. Convert to
      // frame indices so the timeline is fps-independent.
      for (final kf in fig.visibility.values.expand((l) => l)) {
        kf.time = kf.time * fig.fps;
      }
      for (final kf in fig.opacity.values.expand((l) => l)) {
        kf.time = kf.time * fig.fps;
      }
      for (final kf in fig.colors.values.expand((l) => l)) {
        kf.time = kf.time * fig.fps;
      }
      for (final kf in fig.segmentImages.values.expand((l) => l)) {
        kf.time = kf.time * fig.fps;
      }
    }
    fig.ensureDefaultGroup();
    return fig;
  }

  factory Figure.fromJsonString(String json) =>
      Figure.fromJson(jsonDecodeSafe(json));

  /// Builds a standalone figure from [pointIndices], remapping every
  /// index/id-based key and giving each copied segment a fresh id.
  ///
  /// Used by the animation "re-create" flow: a figure deleted at one frame is
  /// hidden (not removed), so bringing it back later must create a NEW object
  /// with its own per-frame state instead of sharing overrides with the
  /// original.
  Figure extractSubFigure(Iterable<int> pointIndices) {
    final keep = pointIndices.toSet()
      ..removeWhere((i) => i < 0 || i >= points.length);
    final ordered = keep.toList()..sort();
    final pointMap = <int, int>{};
    for (var i = 0; i < ordered.length; i++) {
      pointMap[ordered[i]] = i;
    }

    final sub = Figure(name)
      ..canvasWidth = canvasWidth
      ..canvasHeight = canvasHeight
      ..fps = fps
      ..canvasColor = canvasColor;
    for (final old in ordered) {
      sub.points.add(points[old].clone());
    }

    final segIdMap = <String, String>{};
    for (final s in segments) {
      final p1 = pointMap[s.point1Index];
      final p2 = pointMap[s.point2Index];
      if (p1 == null || p2 == null) continue;
      final copy = s.clone();
      final newId = Segment(copy.type).id;
      segIdMap[s.id] = newId;
      copy
        ..id = newId
        ..point1Index = p1
        ..point2Index = p2;
      sub.segments.add(copy);
    }
    sub.rootIndices = rootIndices
        .where(keep.contains)
        .map((r) => pointMap[r]!)
        .toList()
      ..sort();

    visibility.forEach((key, frames) {
      final root = int.tryParse(key);
      if (root == null || !keep.contains(root)) return;
      sub.visibility[pointMap[root]!.toString()] =
          frames.map((kf) => kf.clone()).toList();
    });
    opacity.forEach((key, frames) {
      final root = int.tryParse(key);
      if (root == null || !keep.contains(root)) return;
      sub.opacity[pointMap[root]!.toString()] =
          frames.map((kf) => kf.clone()).toList();
    });
    colors.forEach((key, frames) {
      final root = int.tryParse(key);
      if (root == null || !keep.contains(root)) return;
      sub.colors[pointMap[root]!.toString()] =
          frames.map((kf) => kf.clone()).toList();
    });
    segmentImages.forEach((key, frames) {
      final newId = segIdMap[key];
      if (newId == null) return;
      sub.segmentImages[newId] = frames.map((kf) => kf.clone()).toList();
    });
    figureCollision.forEach((key, value) {
      final root = int.tryParse(key);
      if (root == null || !keep.contains(root)) return;
      sub.figureCollision[pointMap[root]!.toString()] = value;
    });
    cycleFills.forEach((key, entry) {
      final mapped = key
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .map((p) => pointMap[p])
          .whereType<int>()
          .toList();
      if (mapped.length != key.split(',').length || mapped.isEmpty) return;
      mapped.sort();
      sub.cycleFills[mapped.join(',')] = entry.clone();
    });
    attachedSegments.forEach((joint, ids) {
      final newJoint = pointMap[joint];
      if (newJoint == null) return;
      final mappedIds = ids.map((id) => segIdMap[id] ?? id).toList();
      if (mappedIds.isNotEmpty) sub.attachedSegments[newJoint] = mappedIds;
    });

    String? remapOverrideKey(String key) {
      final parts = key.split(':');
      if (parts.length >= 3 && parts[0] == 'seg') {
        final id = segIdMap[parts[1]];
        return id == null ? null : ['seg', id, ...parts.skip(2)].join(':');
      }
      if (parts.length >= 3 && parts[0] == 'cycle') {
        final ids = parts[1]
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .map((p) => pointMap[p])
            .whereType<int>()
            .toList();
        if (ids.isEmpty || ids.length != parts[1].split(',').length) {
          return null;
        }
        ids.sort();
        return ['cycle', ids.join(','), ...parts.skip(2)].join(':');
      }
      return null;
    }

    frameOverrides.forEach((time, values) {
      final mapped = <String, dynamic>{};
      values.forEach((key, value) {
        final newKey = remapOverrideKey(key.toString());
        if (newKey != null) mapped[newKey] = value;
      });
      if (mapped.isNotEmpty) sub.frameOverrides[time] = mapped;
    });

    // Groups keep the SOURCE segment ids here: mergeGroupsFrom() remaps them
    // with segIdMap when the extracted figure is merged back into a scene.
    for (final g in groups) {
      final ids = g.segmentIds.where(segIdMap.keys.contains).toList();
      if (ids.isEmpty) continue;
      sub.groups.add(LayerGroup(
        id: g.id,
        name: g.name,
        segmentIds: ids,
        visible: g.visible,
        locked: g.locked,
      ));
    }
    sub.ensureDefaultGroup();
    return sub;
  }

  Figure clone() => Figure.fromJson(toJson());
}
