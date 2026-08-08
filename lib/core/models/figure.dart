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

  void setFigureVisibility(int root, double time, bool visible) {
    final key = root.toString();
    final track = visibility.putIfAbsent(key, () => []);
    final existing = track
        .where((kf) => (kf.time - time).abs() < 0.001)
        .toList();
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

  void setFigureOpacity(int root, double time, double val) {
    final key = root.toString();
    final track = opacity.putIfAbsent(key, () => []);
    final existing = track
        .where((kf) => (kf.time - time).abs() < 0.001)
        .toList();
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

  void setFigureColorOverride(int root, double time, String color) {
    final key = root.toString();
    final track = colors.putIfAbsent(key, () => []);
    final existing = track.where((kf) => (kf.time - time).abs() < 0.001).toList();
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

  void setSegmentImageIndex(String segId, double time, int imageIndex) {
    final track = segmentImages.putIfAbsent(segId, () => []);
    final existing = track.where((kf) => (kf.time - time).abs() < 0.001).toList();
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
  /// points has at least one root. Existing roots are preserved; a component
  /// that ends up root-less (e.g. after a segment delete or split detaches a
  /// part) gains the lowest point of its component as a new root.
  void repairRoots() {
    if (points.isEmpty) {
      rootIndices = [];
      return;
    }
    final visited = <int>{};
    final newRoots = List.of(rootIndices);
    for (var start = 0; start < points.length; start++) {
      if (visited.contains(start)) continue;
      final comp = connectedComponent(start);
      visited.addAll(comp);
      if (!rootIndices.any(comp.contains)) {
        final root = comp.reduce((a, b) => a < b ? a : b);
        if (root >= 0 && root < points.length && !newRoots.contains(root)) {
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
    if (visibility.isNotEmpty) {
      final newVis = <String, List<VisibilityKeyframe>>{};
      visibility.forEach((k, v) {
        final rk = int.tryParse(k);
        if (rk == null || rk == movedIdx) return;
        newVis[(rk > movedIdx ? rk - 1 : rk).toString()] = v;
      });
      visibility = newVis;
    }
    if (opacity.isNotEmpty) {
      final newOp = <String, List<OpacityKeyframe>>{};
      opacity.forEach((k, v) {
        final rk = int.tryParse(k);
        if (rk == null || rk == movedIdx) return;
        newOp[(rk > movedIdx ? rk - 1 : rk).toString()] = v;
      });
      opacity = newOp;
    }
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
    final newIdx = addPoint(copyX, copyY);
    final seg = segments[segIdx];
    if (seg.point1Index == jointIdx) {
      seg.point1Index = newIdx;
    } else {
      seg.point2Index = newIdx;
    }
    if (!rootIndices.contains(newIdx)) rootIndices.add(newIdx);
    repairRoots();
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
        'groups': groups.map((g) => g.toJson()).toList(),
      };

  /// Segments ordered for painting: group order first (the default group
  /// paints at the bottom, i.e. first), then each group's own [Segment.layer]
  /// order.
  List<Segment> segmentsInDrawOrder() {
    final ordered = orderedGroups();
    final keyOf = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      keyOf[ordered[i].id] = i; // higher = on top (drawn later)
    }
    final sorted = [...segments]..sort((a, b) {
        final ka = keyOf[groupOf(a.id)] ?? 0;
        final kb = keyOf[groupOf(b.id)] ?? 0;
        if (ka != kb) return ka.compareTo(kb);
        return a.layer.compareTo(b.layer);
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

    final rawGroups = data['groups'];
    if (rawGroups is List) {
      fig.groups = rawGroups
          .whereType<Map<String, dynamic>>()
          .map((g) => LayerGroup.fromJson(g))
          .toList();
    }
    fig.ensureDefaultGroup();
    return fig;
  }

  factory Figure.fromJsonString(String json) =>
      Figure.fromJson(jsonDecodeSafe(json));

  Figure clone() => Figure.fromJson(toJson());
}
