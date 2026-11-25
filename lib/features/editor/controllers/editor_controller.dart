import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/figure.dart';
import '../../../core/models/figure_animation.dart';
import '../../../core/models/segment.dart';
import '../../../core/project_storage.dart';

enum EditorMode { figure, animate }

/// Scene mode, independent from [EditorTool]. Exactly one of the three is
/// always active and switching between them never changes the active tool:
/// * [RigMode.rig] – default; normal rig editing.
/// * [RigMode.asset] – same as rig, plus the image asset editor stays active
///   so assets can be adjusted while the rig is still draggable.
/// * [RigMode.anchor] – asset stays anchored in place while rig points move
///   (the image offset compensates), combos with any tool.
enum RigMode { rig, asset, anchor }

enum EditorTool {
  select,
  point,
  modify,
  curve,
  rotate,
  stretch,
  rotateAll,
  line,
  circle,
  image,
  text,
  none,
  asset,
  join,
  anchor,
  attach,
}

extension EditorToolX on EditorTool {
  String get label => switch (this) {
    EditorTool.select => 'Move All',
    EditorTool.point => 'Point',
    EditorTool.modify => 'Modify',
    EditorTool.curve => 'Curve',
    EditorTool.rotate => 'Pivot',
    EditorTool.stretch => 'Scale All',
    EditorTool.rotateAll => 'Rotate All',
    EditorTool.line => 'Line',
    EditorTool.circle => 'Circle',
    EditorTool.image => 'Image',
    EditorTool.text => 'Text',
    EditorTool.none => 'None',
    EditorTool.asset => 'Asset',
    EditorTool.join => 'Join',
    EditorTool.anchor => 'Anchor',
    EditorTool.attach => 'Attach',
  };
}

class CameraTransform {
  final double x;
  final double y;
  final double zoom;

  const CameraTransform({this.x = 0, this.y = 0, this.zoom = 0.8});

  CameraTransform copyWith({double? x, double? y, double? zoom}) =>
      CameraTransform(x: x ?? this.x, y: y ?? this.y, zoom: zoom ?? this.zoom);
}

/// Central editor state, the Flutter analog of `FigureEditorContext.tsx`.
class EditorController extends ChangeNotifier {
  static const int maxHistory = 50;

  String? projectId;
  ProjectType? projectType;

  /// Incremented on every [notifyListeners] call. The canvas painter compares
  /// this in `shouldRepaint` so frame scrubbing, camera moves and any figure
  /// mutation repaint immediately (otherwise Flutter reuses the old painter
  /// and the canvas shows stale colours/curves).
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  Figure? _figure;
  Figure get figure => _figure!;

  String? selectedSegmentId;
  int? selectedPointIndex;
  final Map<int, String> pointModes = {}; // index -> 'dynamic' | 'static'

  /// Points explicitly multi-selected (across figures). Any transform grabs a
  /// selected point and applies to the whole set.
  final Set<int> multiSelection = {};

  /// Grid / point snapping toggled from the editor "More" menu.
  bool _snapEnabled = false;
  bool get snapEnabled => _snapEnabled;
  double snapGrid = 20;

  void setSnapEnabled(bool v) {
    _snapEnabled = v;
    notifyListeners();
  }

  void toggleSnap() => setSnapEnabled(!_snapEnabled);

  void toggleMultiSelect(int index) {
    if (index < 0 || index >= figure.points.length) return;
    if (!multiSelection.add(index)) {
      multiSelection.remove(index);
    }
    setSelectedPoint(index);
    notifyListeners();
  }

  void clearMultiSelect() {
    if (multiSelection.isEmpty) return;
    multiSelection.clear();
    notifyListeners();
  }

  EditorMode editorMode;
  EditorTool activeTool = EditorTool.rotate;
  RigMode rigMode = RigMode.rig;

  final List<String> history = [];
  int historyIndex = -1;

  bool isPlaying = false;
  double currentTime = 0;
  double fps = 12;
  double _duration = 0;
  FigureAnimation? currentAnimation;

  CameraTransform camera = const CameraTransform();
  bool onionPrev = true;
  bool onionNext = false;
  bool autoEasing = true;

  /// Whether to draw connector lines between sub-figures (root points).
  bool _showConnectors = true;
  bool get showConnectors => _showConnectors;

  bool _showAxis = false;
  bool get showAxis => _showAxis;

  bool _panEnabled = true;
  bool get panEnabled => _panEnabled;

  /// The image segment currently being edited in asset mode (by id).
  String? assetSegmentId;

  void toggleConnectors() {
    _showConnectors = !_showConnectors;
    forceUpdate();
  }

  void toggleAxis() {
    _showAxis = !_showAxis;
    forceUpdate();
  }

  void togglePanEnabled() {
    _panEnabled = !_panEnabled;
    notifyListeners();
  }

  /// Selects an image segment for the asset editor.
  void selectAssetSegment(String? id) {
    assetSegmentId = id;
    setSelectedSegment(id);
    setSelectedPoint(null);
    notifyListeners();
  }

  Timer? _playbackTimer;
  bool loaded = false;

  // Original points snapshot while animate mode applies animation.
  List<Point2>? _savedPoints;

  EditorController({
    required this.editorMode,
    this.projectId,
    this.projectType,
    Figure? initialFigure,
    FigureAnimation? initialAnimation,
  }) : _figure = initialFigure {
    currentAnimation = initialAnimation;
    if (initialFigure != null) {
      fps = initialFigure.fps;
      _duration = initialAnimation?.duration ?? 0;
    }
  }

  double get duration => _duration;
  bool get canUndo => historyIndex > 0;
  bool get canRedo => historyIndex < history.length - 1;

  bool get isAnimateMode => editorMode == EditorMode.animate;

  /// Preset and Animation projects both use the animated editor (so every tool
  /// auto-keys), but only Animation is a finished movie: it has no reusable
  /// Lottie/game asset to export.
  bool get isPresetProject => projectType == ProjectType.preset;
  bool get isAnimationProject => projectType == ProjectType.animation;

  double get frameDuration => 1.0 / fps;
  int get totalFrames => duration <= 0 ? 1 : duration.round().clamp(1, 1000000);
  int get currentFrame => currentTime.round().clamp(0, totalFrames - 1);

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  static Future<EditorController> load({
    required EditorMode mode,
    String? projectId,
    ProjectType? projectType,
  }) async {
    var figure = Figure();
    FigureAnimation? anim;

    if (projectId != null) {
      final meta = await ProjectStorage.getProject(projectId);
      if (meta != null) {
        figure.name = meta.name;
        projectType ??= meta.type;
      }
      final data = await ProjectStorage.loadProjectData(projectId);
      if (data != null) {
        if (data.figure != null) {
          final parsed = Figure.fromJsonString(data.figure!);
          if (parsed.segments.isNotEmpty) figure = parsed;
        }
        if (data.animation != null) {
          anim = FigureAnimation.fromJsonString(
            data.animation!,
            legacyFps: figure.fps,
          );
        }
      }
    }

    // A brand-new preset/animation has no saved animation yet. Create an empty
    // one so per-frame overrides work immediately (scrubbing, preview, GIF/PNG
    // and Lottie export all check for a non-null animation before applying
    // overrides).
    if (mode == EditorMode.animate) {
      anim ??= FigureAnimation('Animation');
    }

    final controller = EditorController(
      editorMode: mode,
      projectId: projectId,
      projectType: projectType,
      initialFigure: figure,
      initialAnimation: anim,
    );
    controller.loaded = true;
    controller._syncPointModesFromFigure();
    controller._pushHistory(force: true);
    controller.notifyListeners();
    return controller;
  }

  // -------------------------------------------------------------------------
  // Mutation + save
  // -------------------------------------------------------------------------

  void forceUpdate() {
    notifyListeners();
    _scheduleSave();
  }

  // -- Generic per-frame overrides -------------------------------------------
  // Used by tools that edit structural properties (width, curve handles,
  // image transform, text, per-segment colour/hidden/layer...). The base
  // Figure field still holds the newest value; these snapshots keep earlier
  // frames looking the way they did before the edit.

  void captureFrameOverride(String key, dynamic oldValue) {
    if (!isAnimateMode) return;
    figure.captureFrameOverride(key, oldValue);
  }

  void setFrameOverride(String key, dynamic value) {
    if (!isAnimateMode) return;
    figure.setFrameOverride(key, value, currentTime);
    forceUpdate();
  }

  Set<double> authoredFrameTimes() {
    final times = figure.authoredFrameTimes();
    final anim = currentAnimation;
    if (anim != null) {
      for (final track in anim.tracks) {
        for (final kf in track.keyframes) {
          times.add(kf.time.roundToDouble());
        }
      }
    }
    times.add(currentTime.roundToDouble());
    return times;
  }

  /// Captures the old value at frame 0 (once), writes [value] at the current
  /// frame and protects later frames from leaking the new value into them.
  ///
  /// Unlike [setFrameOverride] this does not notify listeners, so a drag can
  /// batch several properties into one repaint.
  void recordFrameValue(String key, dynamic oldValue, dynamic value) {
    if (!isAnimateMode || oldValue == value) return;
    final t = currentTime.roundToDouble();
    figure.captureFrameOverride(key, oldValue);
    figure.protectNextOverrideBoundary(key, t, oldValue, authoredFrameTimes());
    // Snapshot the OLD resolved values at later frames BEFORE the edit, so the
    // new value does not hold forward into frames that have no own override.
    final laterOld = <double, dynamic>{};
    final last = duration.floor();
    for (var f = t.toInt() + 1; f <= last; f++) {
      final tt = f.toDouble();
      if (figure.hasFrameOverride(key, tt)) continue;
      laterOld[tt] = figure.frameObject(key, tt, oldValue);
    }
    figure.setFrameOverride(key, value, t);
    for (final e in laterOld.entries) {
      figure.frameOverrides.putIfAbsent(e.key, () => <String, dynamic>{})[key] =
          e.value;
    }
  }

  void recordSegmentValue(
    Segment seg,
    String property,
    dynamic oldValue,
    dynamic value,
  ) {
    recordFrameValue('seg:${seg.id}:$property', oldValue, value);
  }

  void recordCycleValue(
    String cycleKey,
    String property,
    dynamic oldValue,
    dynamic value,
  ) {
    recordFrameValue('cycle:$cycleKey:$property', oldValue, value);
  }

  /// Marks a freshly drawn [seg] as hidden before the current frame and
  /// visible from the current frame onward, when animated. Later authored
  /// frames are protected so the new object does not leak into them.
  void markSegmentBornAtCurrentFrame(Segment seg) {
    if (!isAnimateMode) return;
    final key = 'seg:${seg.id}:hidden';
    figure.captureFrameOverride(key, true);
    figure.protectNextOverrideBoundary(
      key,
      currentTime,
      true,
      authoredFrameTimes(),
    );
    figure.setFrameOverride(key, false, currentTime);
    forceUpdate();
  }

  /// Records a point pose at [time] (defaults to [currentTime]) while
  /// protecting later authored frames from leaking. The next authored frame
  /// keeps its old value, and when there is a gap we also pin [T+1] so an
  /// earlier edit does not ripple through untouched later frames.
  void recordPointPose(
    int pointIndex,
    double x,
    double y, {
    Set<double>? authoredTimes,
    double? time,
  }) {
    if (!isAnimateMode) return;
    final anim = ensureAnimation();
    final t = (time ?? currentTime).roundToDouble();
    final times = authoredTimes ?? authoredFrameTimes();
    final track = anim.getTrack(pointIndex);
    final tRound = t.roundToDouble();
    // Seed frame 0 when this is the first keyframe for the track, so earlier
    // frames keep the base pose instead of snapping to the new value.
    if (tRound > 0) {
      times.add(0.0);
      final hasPrevKf =
          track?.keyframes.any((kf) => kf.time < tRound - 0.0001) ?? false;
      if (!hasPrevKf) {
        final base =
            (track?.getValue(0, autoEasing)) ??
            ((pointIndex >= 0 &&
                    _savedPoints != null &&
                    pointIndex < _savedPoints!.length)
                ? PointKeyframe(
                    0,
                    _savedPoints![pointIndex].x,
                    _savedPoints![pointIndex].y,
                  )
                : (pointIndex >= 0 && pointIndex < figure.points.length)
                ? PointKeyframe(
                    0,
                    figure.points[pointIndex].x,
                    figure.points[pointIndex].y,
                  )
                : null);
        if (base != null) {
          anim.setPointPose(0, pointIndex, base.x, base.y);
        }
      }
    }
    double? next;
    for (final at in times) {
      final rt = at.roundToDouble();
      if (rt > tRound && (next == null || rt < next)) next = rt;
    }
    // Protect previous boundary so interpolation before t keeps old shape.
    double? prev;
    for (final at in times) {
      final rt = at.roundToDouble();
      if (rt < tRound && (prev == null || rt > prev)) prev = rt;
    }
    if (prev != null) {
      final tPrevCut = tRound - 0.001;
      if (tPrevCut > prev) {
        final hasPrevCut =
            track?.keyframes.any((kf) => (kf.time - tPrevCut).abs() < 0.001) ??
            false;
        if (!hasPrevCut) {
          final oldPrev = track?.getValue(tPrevCut, autoEasing);
          if (oldPrev != null) {
            anim.setPointPose(tPrevCut, pointIndex, oldPrev.x, oldPrev.y);
          } else if (pointIndex >= 0 && pointIndex < figure.points.length) {
            final p = figure.points[pointIndex];
            anim.setPointPose(tPrevCut, pointIndex, p.x, p.y);
          }
        }
      }
    }

    if (next != null) {
      final hasNext =
          track?.keyframes.any((kf) => (kf.time - next!).abs() < 0.001) ??
          false;
      if (!hasNext) {
        final old = track?.getValue(next, autoEasing);
        if (old != null) {
          anim.setPointPose(next, pointIndex, old.x, old.y);
        } else if (pointIndex >= 0 && pointIndex < figure.points.length) {
          final p = figure.points[pointIndex];
          anim.setPointPose(next, pointIndex, p.x, p.y);
        }
      }
      // Pin just after t so interpolation does not bleed into later frames.
      // Use +0.001: invisible to onion skin (poseAt uses 0.001 threshold) and
      // small enough to avoid visible interpolation.
      final tCut = tRound + 0.001;
      if (tCut < next) {
        final hasCut =
            track?.keyframes.any((kf) => (kf.time - tCut).abs() < 0.001) ??
            false;
        if (!hasCut) {
          final oldCut = track?.getValue(tCut, autoEasing);
          if (oldCut != null) {
            anim.setPointPose(tCut, pointIndex, oldCut.x, oldCut.y);
          } else if (pointIndex >= 0 && pointIndex < figure.points.length) {
            final p = figure.points[pointIndex];
            anim.setPointPose(tCut, pointIndex, p.x, p.y);
          }
        }
      }
    }
    anim.setPointPose(t, pointIndex, x, y);
    final track2 = anim.getTrack(pointIndex);
    if (track2 != null) {
      final last = duration.floor();
      for (var f = 0; f <= last; f++) {
        final ft = f.toDouble();
        if (track2.keyframes.any((kf) => (kf.time - ft).abs() < 0.001))
          continue;
        final val = track2.getValue(ft, autoEasing);
        if (val != null) {
          track2.addKeyframe(ft, val.x, val.y);
        }
      }
    }
    if (anim.duration > duration) setDuration(anim.duration);
  }

  /// Writes point positions at the current frame (used when a tool creates
  /// brand-new points outside the normal drag recorder).
  void recordPointsAtCurrentFrame(Iterable<int> indices) {
    if (!isAnimateMode) return;
    final times = authoredFrameTimes();
    for (final i in indices) {
      if (i < 0 || i >= figure.points.length) continue;
      final p = figure.points[i];
      recordPointPose(i, p.x, p.y, authoredTimes: times);
    }
    forceUpdate();
  }

  void _scheduleSave() {
    final id = projectId;
    if (id == null || _figure == null) return;
    // Debounce save to storage.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () async {
      await ProjectStorage.saveProjectData(
        id,
        ProjectData(
          figure: figure.exportToJson(),
          animation: currentAnimation?.exportToJson(),
        ),
      );
    });
  }

  Timer? _saveDebounce;

  void disposeSave() {
    _saveDebounce?.cancel();
  }

  void setFigure(Figure? f) {
    _figure = f;
    notifyListeners();
  }

  void setSelectedSegment(String? id) {
    selectedSegmentId = id;
    notifyListeners();
  }

  void setSelectedPoint(int? index) {
    selectedPointIndex = index;
    notifyListeners();
  }

  void setTool(EditorTool tool) {
    activeTool = tool;
    notifyListeners();
  }

  /// Switches the scene mode (rig/asset/anchor). Never changes [activeTool].
  void setRigMode(RigMode mode) {
    rigMode = mode;
    notifyListeners();
  }

  bool get isAssetMode => rigMode == RigMode.asset;
  bool get isAnchorMode => rigMode == RigMode.anchor;

  void setEditorMode(EditorMode mode) {
    editorMode = mode;
    notifyListeners();
  }

  void togglePointMode(int index) {
    final current = pointModes[index];
    if (current == 'static') {
      pointModes[index] = 'dynamic';
      if (index >= 0 && index < figure.points.length) {
        figure.points[index].isStatic = false;
      }
    } else {
      pointModes[index] = 'static';
      if (index >= 0 && index < figure.points.length) {
        figure.points[index].isStatic = true;
      }
    }
    notifyListeners();
  }

  bool isPointStatic(int index) => pointModes[index] == 'static';

  /// Rebuilds [pointModes] from the figure's persisted per-point static flags.
  void _syncPointModesFromFigure() {
    pointModes.clear();
    if (_figure == null) return;
    for (var i = 0; i < _figure!.points.length; i++) {
      if (_figure!.points[i].isStatic) {
        pointModes[i] = 'static';
      }
    }
  }

  /// Adds a brand-new segment (which always has two points) as a new
  /// sub-figure: the first point becomes a new root so it gets its own
  /// visibility track. The points are placed near the centre of the canvas.
  int addSegment(String type) {
    if (_figure == null) return -1;
    final seg = _figure!.addSegment(type);
    final root = seg.point1Index;
    if (!_figure!.rootIndices.contains(root)) {
      _figure!.rootIndices.add(root);
    }
    setSelectedSegment(seg.id);
    setSelectedPoint(seg.point2Index);
    markSegmentBornAtCurrentFrame(seg);
    recordPointsAtCurrentFrame([root, seg.point2Index]);
    forceUpdate();
    pushHistory();
    return root;
  }

  int addSegmentWithImage(String imageData) {
    if (_figure == null) return -1;
    final seg = _figure!.addSegment('image');
    seg.imageData = imageData;
    seg.imageWidth = 100;
    seg.imageHeight = 'auto';
    final root = seg.point1Index;
    if (!_figure!.rootIndices.contains(root)) {
      _figure!.rootIndices.add(root);
    }
    setSelectedSegment(seg.id);
    setSelectedPoint(seg.point2Index);
    markSegmentBornAtCurrentFrame(seg);
    recordPointsAtCurrentFrame([root, seg.point2Index]);
    forceUpdate();
    pushHistory();
    return root;
  }

  /// Merges the dragged point into [targetIdx]; the surviving (target) root
  /// is kept and the moved point's root is dropped.
  int joinPoints(int movedIdx, int targetIdx) {
    if (_figure == null) return targetIdx;
    final target = _figure!.joinPoints(movedIdx, targetIdx);
    setSelectedPoint(target);
    pointModes.remove(movedIdx);
    final remapped = <int, String>{};
    pointModes.forEach((k, v) {
      if (k > movedIdx) {
        remapped[k - 1] = v;
      } else if (k != movedIdx) {
        remapped[k] = v;
      }
    });
    pointModes.clear();
    pointModes.addAll(remapped);
    multiSelection.clear();
    if (currentAnimation != null) {
      currentAnimation!.tracks.removeWhere((t) => t.pointIndex == movedIdx);
      for (final t in currentAnimation!.tracks) {
        if (t.pointIndex > movedIdx) t.pointIndex--;
      }
    }
    forceUpdate();
    pushHistory();
    return target;
  }

  /// Splits the joint point so it detaches from [detachFromIdx], giving the
  /// detached segment its own root at [copyX],[copyY].
  int? splitJoint(int ptIdx, int detachFromIdx, double copyX, double copyY) {
    if (_figure == null) return null;
    final newIdx = _figure!.splitJoint(ptIdx, detachFromIdx, copyX, copyY);
    if (newIdx < 0) return null;
    // The copied point is brand new in this frame: give it its own pose
    // keyframe so the anchored side stays put when the timeline is scrubbed.
    recordPointsAtCurrentFrame([ptIdx, newIdx]);
    setSelectedPoint(ptIdx);
    pushHistory();
    forceUpdate();
    return newIdx;
  }

  // -------------------------------------------------------------------------
  // Layer groups
  // -------------------------------------------------------------------------

  /// Creates a new, empty layer group.
  void addLayerGroup({String? name}) {
    if (_figure == null) return;
    _figure!.groups.add(
      LayerGroup(
        id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
        name: name ?? 'Group ${_figure!.groups.length}',
      ),
    );
    pushHistory();
    forceUpdate();
  }

  /// Removes a layer group, moving its segments to the default group. The
  /// default group itself cannot be removed.
  void removeLayerGroup(String id) {
    if (_figure == null || id == Figure.defaultGroupId) return;
    final idx = _figure!.groups.indexWhere((g) => g.id == id);
    if (idx == -1) return;
    final removed = _figure!.groups.removeAt(idx);
    for (final segId in removed.segmentIds) {
      _figure!.moveSegmentToGroup(segId, Figure.defaultGroupId);
    }
    pushHistory();
    forceUpdate();
  }

  /// Renames a layer group.
  void renameLayerGroup(String id, String name) {
    if (_figure == null) return;
    final group = _figure!.groups.where((g) => g.id == id).firstOrNull;
    if (group == null || group.id == Figure.defaultGroupId) return;
    group.name = name.trim().isEmpty ? group.name : name.trim();
    pushHistory();
    forceUpdate();
  }

  /// Toggles visibility of a group; hides/shows its segments.
  void toggleGroupVisible(String id) {
    if (_figure == null) return;
    final group = _figure!.groups.where((g) => g.id == id).firstOrNull;
    if (group == null) return;
    group.visible = !group.visible;
    pushHistory();
    forceUpdate();
  }

  /// Toggles locking of a group.
  void toggleGroupLocked(String id) {
    if (_figure == null) return;
    final group = _figure!.groups.where((g) => g.id == id).firstOrNull;
    if (group == null) return;
    group.locked = !group.locked;
    pushHistory();
    forceUpdate();
  }

  /// Moves a segment into the given group (falls back to default).
  void moveSegmentToGroup(String segId, String groupId) {
    if (_figure == null) return;
    _figure!.moveSegmentToGroup(segId, groupId);
    pushHistory();
    forceUpdate();
  }

  /// Moves a segment into a group AND reorders it at [index] inside it.
  void placeSegmentInGroup(String segId, String groupId, int index) {
    if (_figure == null) return;
    _figure!.placeSegmentInGroup(segId, groupId, index);
    pushHistory();
    forceUpdate();
  }

  /// Reorders segments inside [groupId].
  void reorderSegmentsInGroup(String groupId, List<String> orderedIds) {
    if (_figure == null) return;
    _figure!.reorderSegmentsInGroup(groupId, orderedIds);
    pushHistory();
    forceUpdate();
  }

  /// Id of the group that owns [segId].
  String groupOf(String segId) =>
      _figure?.groupOf(segId) ?? Figure.defaultGroupId;

  /// Reorders layer groups (non-default). [oldIndex]/[newIndex] are indices
  /// among the non-default groups in panel order.
  void reorderLayerGroups(int oldIndex, int newIndex) {
    if (_figure == null) return;
    _figure!.reorderGroups(oldIndex, newIndex);
    pushHistory();
    forceUpdate();
  }

  /// Whether the segment belongs to a locked group (blocks editing).
  bool isInLockedGroup(String segId) {
    if (_figure == null) return false;
    final groupId = _figure!.groupOf(segId);
    final group = _figure!.groups.where((g) => g.id == groupId).firstOrNull;
    return group?.locked ?? false;
  }

  // -------------------------------------------------------------------------
  // Camera
  // -------------------------------------------------------------------------

  void zoomIn() =>
      camera = camera.copyWith(zoom: (camera.zoom * 1.2).clamp(0.1, 5.0));
  void zoomOut() =>
      camera = camera.copyWith(zoom: (camera.zoom / 1.2).clamp(0.1, 5.0));
  void zoomReset() => camera = const CameraTransform();

  void setCamera(CameraTransform c) {
    camera = c;
    notifyListeners();
  }

  void moveCamera(double dx, double dy) {
    camera = camera.copyWith(x: camera.x + dx, y: camera.y + dy);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Undo / redo
  // -------------------------------------------------------------------------

  void _pushHistory({bool force = false}) {
    if (_figure == null) return;
    final jsonStr = figure.exportToJson();
    if (!force &&
        historyIndex >= 0 &&
        historyIndex < history.length &&
        history[historyIndex] == jsonStr) {
      return;
    }
    if (history.length > historyIndex + 1) {
      history.removeRange(historyIndex + 1, history.length);
    }
    history.add(jsonStr);
    if (history.length > maxHistory) history.removeAt(0);
    historyIndex = history.length - 1;
  }

  void pushHistory() {
    _pushHistory();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    historyIndex--;
    _figure = Figure.fromJsonString(history[historyIndex]);
    _resetSelection();
    notifyListeners();
    _scheduleSave();
  }

  void redo() {
    if (!canRedo) return;
    historyIndex++;
    _figure = Figure.fromJsonString(history[historyIndex]);
    _resetSelection();
    notifyListeners();
    _scheduleSave();
  }

  void _resetSelection() {
    selectedSegmentId = null;
    selectedPointIndex = null;
  }

  // -------------------------------------------------------------------------
  // Remove sub-figure
  // -------------------------------------------------------------------------

  void removeFigureAt(int rootIndex) {
    if (_figure == null) return;
    final removed = figure.removeFigure(rootIndex);
    if (removed == null) return;
    int remap(int i) {
      var n = i;
      for (final r in removed) {
        if (r < n) n--;
      }
      return n;
    }

    final anim = currentAnimation;
    if (anim != null) {
      anim.tracks.removeWhere((t) => removed.contains(t.pointIndex));
      for (final t in anim.tracks) {
        t.pointIndex = remap(t.pointIndex);
      }
    }
    pointModes.removeWhere((k, _) => removed.contains(k));
    final remapped = <int, String>{};
    pointModes.forEach((k, v) => remapped[remap(k)] = v);
    pointModes.clear();
    pointModes.addAll(remapped);
    multiSelection.clear();
    _resetSelection();
    pushHistory();
    forceUpdate();
  }

  void centerFigureAt(int ptIdx) {
    if (_figure == null) return;
    final comp = figure.connectedComponent(ptIdx);
    final root = figure.rootIndices.firstWhere(
      (r) => comp.contains(r),
      orElse: () => -1,
    );
    if (root == -1) return;

    final rootPt = figure.points[root];
    final dx = -rootPt.x;
    final dy = -rootPt.y;

    for (final idx in comp) {
      if (idx >= 0 && idx < figure.points.length) {
        final p = figure.points[idx];
        p.x += dx;
        p.y += dy;
      }
    }
    pushHistory();
    forceUpdate();
  }

  void toggleFigureVisibility(int ptIdx) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;

    final isVisible = figure.getFigureVisibility(root, currentTime);
    figure.setFigureVisibility(
      root,
      currentTime,
      !isVisible,
      authoredTimes: authoredFrameTimes(),
    );
    final last = duration.floor();
    for (var f = 0; f <= last; f++) {
      final t = f.toDouble();
      final track = figure.visibility[root.toString()];
      if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
        continue;
      }
      figure.setFigureVisibility(root, t, figure.getFigureVisibility(root, t));
    }

    pushHistory();
    forceUpdate();
  }

  /// Animation-project delete. Writes a visibility `false` keyframe at
  /// [currentTime]; hold semantics keep the object visible in every earlier
  /// frame, exactly like the visibility tool. Nothing is removed from the
  /// figure, so a later frame can still re-create it.
  void hideFigureAtCurrentFrame(int ptIdx) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;
    figure.setFigureVisibility(
      root,
      currentTime,
      false,
      authoredTimes: authoredFrameTimes(),
    );
    final last = duration.floor();
    for (var f = 0; f <= last; f++) {
      final t = f.toDouble();
      final track = figure.visibility[root.toString()];
      if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
        continue;
      }
      figure.setFigureVisibility(root, t, figure.getFigureVisibility(root, t));
    }
    pushHistory();
    forceUpdate();
  }

  /// Animation-project "re-create". Brings a deleted object back as a NEW
  /// object starting at [currentTime]: fresh segment ids, remapped overrides
  /// and a visibility keyframe pair (hidden before, visible from here).
  /// The original object is untouched, so earlier frames stay unchanged.
  List<int>? recreateFigureAtCurrentFrame(int ptIdx) {
    if (_figure == null) return null;
    final comp = figure.connectedComponent(ptIdx);
    if (comp.isEmpty) return null;
    final sub = figure.extractSubFigure(comp);
    if (sub.points.isEmpty || sub.segments.isEmpty) return null;

    final newPoints = mergeImportedFigure(sub);
    if (newPoints.isNotEmpty) setSelectedPoint(newPoints.first);
    return newPoints;
  }

  /// Merges [src] into the current figure as a NEW object with fresh ids.
  /// Returns the new point indices so callers can key their pose at
  /// [currentTime] (animation/preset imports must not depend on whichever
  /// frame happened to be active in the source project).
  List<int> mergeImportedFigure(Figure src) {
    if (src.points.isEmpty) return const <int>[];
    final srcPts = src.points;
    final xs = srcPts.map((p) => p.x).toList();
    final ys = srcPts.map((p) => p.y).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final curMaxX = figure.points.isEmpty
        ? -100
        : figure.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final offsetX = curMaxX + 100 - minX;
    final offsetY = -((minY + maxY) / 2);

    final indexMap = <int, int>{};
    final base = figure.points.length;
    for (var i = 0; i < srcPts.length; i++) {
      indexMap[i] = base + i;
      figure.points.add(Point2(srcPts[i].x + offsetX, srcPts[i].y + offsetY));
    }
    final roots = figure.rootIndices;
    final newRoots = <int>[];
    for (final r in src.rootIndices) {
      final mapped = indexMap[r];
      if (mapped == null) continue;
      newRoots.add(mapped);
      if (!roots.contains(mapped)) roots.add(mapped);
    }
    if (isAnimateMode) {
      final authoredTimes = authoredFrameTimes();
      for (final r in newRoots) {
        final t = currentTime.roundToDouble();
        // New objects must not leak into later authored frames.
        figure.setFigureVisibility(r, 0.0, false);
        if (t > 0.001) {
          figure.setFigureVisibility(r, t, true, authoredTimes: authoredTimes);
        } else {
          // At frame 0: make visible now, but keep later authored frames hidden.
          figure.setFigureVisibility(r, 0.0, true);
          final next = authoredTimes
              .where((at) => at.roundToDouble() > 0.0)
              .fold<double?>(null, (p, at) {
                final rt = at.roundToDouble();
                return p == null || rt < p ? rt : p;
              });
          if (next != null) {
            figure.visibility
                .putIfAbsent(r.toString(), () => [])
                .removeWhere((kf) => (kf.time - next).abs() < 0.001);
            figure.visibility[r.toString()]!.add(
              VisibilityKeyframe(next, false),
            );
            figure.visibility[r.toString()]!.sort(
              (a, b) => a.time.compareTo(b.time),
            );
          }
        }
      }
    }
    final segIdMap = <String, String>{};
    for (final s in src.segments) {
      final p1 = indexMap[s.point1Index];
      final p2 = indexMap[s.point2Index];
      if (p1 == null || p2 == null) continue;
      final ns = s.clone();
      // Per-frame overrides are keyed by segment id. Cloning must give the
      // imported copy fresh ids, otherwise editing one object also changes
      // every other object that shares the original id.
      final newId = Segment(ns.type).id;
      segIdMap[s.id] = newId;
      ns.id = newId;
      ns.point1Index = p1;
      ns.point2Index = p2;
      ns.layer = ns.layer + figure.segments.length;
      figure.segments.add(ns);
    }

    // Remap attachment bookkeeping, cycle-fill keys (point indices) and
    // override keys so imported objects keep their own state and detach safely.
    src.remappedAttachedSegments(segIdMap, indexMap).forEach((joint, ids) {
      figure.attachedSegments[joint] = ids;
    });
    src.cycleFills.forEach((key, entry) {
      final mapped = key
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .map((p) => indexMap[p])
          .whereType<int>()
          .toList();
      if (mapped.length == key.split(',').length && mapped.isNotEmpty) {
        mapped.sort();
        figure.cycleFills[mapped.join(',')] = entry.clone();
      }
    });
    String? remapKey(String key) {
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
            .toList();
        final mapped = ids.map((p) => indexMap[p]).whereType<int>().toList();
        if (mapped.length != ids.length) return null;
        mapped.sort();
        return ['cycle', mapped.join(','), ...parts.skip(2)].join(':');
      }
      return key;
    }

    src.frameOverrides.forEach((frame, values) {
      final mapped = <String, dynamic>{};
      values.forEach((key, value) {
        final newKey = remapKey(key.toString());
        if (newKey != null) mapped[newKey] = value;
      });
      if (mapped.isNotEmpty) {
        figure.frameOverrides[frame] = Map<String, dynamic>.from(
          figure.frameOverrides[frame] ?? {},
        )..addAll(mapped);
      }
    });

    mergeGroupsFrom(src, segIdMap);
    final newPointIndices = indexMap.values.toList();
    recordPointsAtCurrentFrame(newPointIndices);
    forceUpdate();
    pushHistory();
    return newPointIndices;
  }

  void mergeGroupsFrom(Figure src, [Map<String, String>? segIdMap]) {
    final present = {for (final s in figure.segments) s.id};
    for (final g in src.groups) {
      if (g.id == Figure.defaultGroupId) continue;
      final ids = g.segmentIds
          .map((id) => segIdMap?[id] ?? id)
          .where(present.contains)
          .toList();
      if (ids.isEmpty) continue;
      figure.groups.add(
        LayerGroup(
          name: g.name,
          segmentIds: ids,
          visible: g.visible,
          locked: g.locked,
        ),
      );
    }
    figure.ensureDefaultGroup();
    figure.ensureSegmentsInDefaultGroup();
  }

  void setFigureOpacity(int ptIdx, double val) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;

    figure.setFigureOpacity(
      root,
      currentTime,
      val,
      authoredTimes: authoredFrameTimes(),
    );
    final last = duration.floor();
    for (var f = 0; f <= last; f++) {
      final t = f.toDouble();
      final track = figure.opacity[root.toString()];
      if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
        continue;
      }
      figure.setFigureOpacity(root, t, figure.getFigureOpacity(root, t));
    }

    pushHistory();
    forceUpdate();
  }

  /// Resolves the per-figure key for [ptIdx]. Uses [Figure.figureKeyFor] so
  /// overrides (visibility/opacity/color) stay scoped to a single figure, even
  /// when the figure was attached to another (attached figures keep a joint
  /// separated from the merged root).
  int _figureKeyForPoint(int ptIdx) {
    if (ptIdx < 0 || ptIdx >= figure.points.length) return -1;
    return figure.figureKeyFor(ptIdx);
  }

  /// Returns a point index that belongs to the currently-selected figure,
  /// honouring attached joints. For a selected segment whose endpoint is the
  /// attached joint (that endpoint maps to the HOST figure), the endpoint on
  /// the attachment side is returned so figure-scoped overrides
  /// (colour/visibility/opacity/collision) target the right figure.
  int? selectedFigurePoint() {
    if (_figure == null) return null;
    final segId = selectedSegmentId;
    if (segId != null) {
      final seg = figure.getSegment(segId);
      if (seg != null) {
        final k = figure.segmentFigureKey(seg);
        for (final idx in [seg.point1Index, seg.point2Index]) {
          if (idx >= 0 &&
              idx < figure.points.length &&
              figure.figureKeyFor(idx) == k) {
            return idx;
          }
        }
        if (k >= 0 && k < figure.points.length) return k;
        return null;
      }
    }
    final pt = selectedPointIndex;
    if (pt != null && pt >= 0 && pt < figure.points.length) return pt;
    return null;
  }

  void setFigureColorOverride(int ptIdx, String color) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;

    figure.setFigureColorOverride(
      root,
      currentTime,
      color,
      authoredTimes: authoredFrameTimes(),
    );
    final last = duration.floor();
    for (var f = 0; f <= last; f++) {
      final t = f.toDouble();
      final track = figure.colors[root.toString()];
      if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
        continue;
      }
      final v = figure.getFigureColorOverride(root, t);
      if (v != null) figure.setFigureColorOverride(root, t, v);
    }

    pushHistory();
    forceUpdate();
  }

  /// The figure-wide colour override applied, place as the current frame, or
  /// null when the figure uses its natural segment colours.
  String? figureColorOverrideAt(int ptIdx) {
    if (_figure == null || !isAnimateMode) return null;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return null;
    return figure.getFigureColorOverride(root, currentTime);
  }

  /// Removes the figure-wide colour override keyframe at the current time.
  void clearFigureColorOverride(int ptIdx) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;
    figure.removeFigureColorOverride(root, currentTime);
    pushHistory();
    forceUpdate();
  }

  /// Adds another image to a segment's sprite list and makes it the active
  /// image (figure mode only; the list is structural).
  void addSegmentImage(String segId, String data) {
    if (_figure == null) return;
    final seg = figure.getSegment(segId);
    if (seg == null) return;
    seg.imageDataList.add(data);
    seg.activeImageIndex = seg.imageDataList.length - 1;
    pushHistory();
    forceUpdate();
  }

  /// Removes an image at [index] from a segment's sprite list and renumbers
  /// any frame keyframes pointing past it.
  void removeSegmentImage(String segId, int index) {
    if (_figure == null) return;
    final seg = figure.getSegment(segId);
    if (seg == null || index < 0 || index >= seg.imageDataList.length) return;
    seg.imageDataList.removeAt(index);
    if (seg.activeImageIndex >= seg.imageDataList.length) {
      seg.activeImageIndex = seg.imageDataList.isEmpty
          ? 0
          : seg.imageDataList.length - 1;
    }
    final tracks = figure.segmentImages[segId];
    if (tracks != null) {
      tracks.removeWhere((kf) => kf.imageIndex == index);
      for (final kf in tracks) {
        if (kf.imageIndex > index) kf.imageIndex--;
      }
      if (tracks.isEmpty) figure.segmentImages.remove(segId);
    }
    pushHistory();
    forceUpdate();
  }

  /// Selects an image of a segment's sprite list. In preset/animate mode the
  /// selection is recorded as a per-frame keyframe; in figure mode it sets the
  /// active image directly.
  void selectSegmentImage(String segId, int imageIndex) {
    if (_figure == null) return;
    final seg = figure.getSegment(segId);
    if (seg == null || seg.imageDataList.isEmpty) return;
    final clamped = imageIndex < 0
        ? 0
        : imageIndex >= seg.imageDataList.length
        ? seg.imageDataList.length - 1
        : imageIndex;
    if (isAnimateMode) {
      figure.setSegmentImageIndex(
        segId,
        currentTime,
        clamped,
        authoredTimes: authoredFrameTimes(),
      );
      final last = duration.floor();
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final track = figure.segmentImages[segId];
        if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
          continue;
        }
        final v = figure.getSegmentImageIndex(segId, t);
        if (v != null) figure.setSegmentImageIndex(segId, t, v);
      }
    } else {
      seg.activeImageIndex = clamped;
    }
    pushHistory();
    forceUpdate();
  }

  void setSegmentImageIndex(String segId, int imageIndex) {
    if (_figure == null) return;
    figure.setSegmentImageIndex(
      segId,
      currentTime,
      imageIndex,
      authoredTimes: authoredFrameTimes(),
    );
    final last = duration.floor();
    for (var f = 0; f <= last; f++) {
      final t = f.toDouble();
      final track = figure.segmentImages[segId];
      if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
        continue;
      }
      final v = figure.getSegmentImageIndex(segId, t);
      if (v != null) figure.setSegmentImageIndex(segId, t, v);
    }
    pushHistory();
    forceUpdate();
  }

  /// Swaps the currently-active image of a segment with [data] (a data URI)
  /// without touching the rig (points/connections stay intact). Works in both
  /// figure and preset/animate modes.
  void swapSegmentImage(String segId, String data) {
    if (_figure == null) return;
    final seg = figure.getSegment(segId);
    if (seg == null) return;
    final idx = isAnimateMode
        ? (figure.getSegmentImageIndex(segId, currentTime) ??
              seg.activeImageIndex)
        : seg.activeImageIndex;
    if (seg.imageDataList.isEmpty) {
      seg.imageDataList.add(data);
    } else {
      seg.imageDataList[idx.clamp(0, seg.imageDataList.length - 1)] = data;
    }
    seg.activeImageIndex = idx.clamp(0, seg.imageDataList.length - 1);
    pushHistory();
    forceUpdate();
  }

  /// Toggles the game-dev collision flag for the whole figure containing
  /// [ptIdx] (scoped per figure, following the visibility/opacity pattern).
  void toggleFigureCollision(int ptIdx) {
    if (_figure == null) return;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return;
    figure.setFigureCollision(root, !figure.getFigureCollision(root));
    pushHistory();
    forceUpdate();
  }

  bool isFigureCollision(int ptIdx) {
    if (_figure == null) return false;
    final root = _figureKeyForPoint(ptIdx);
    if (root == -1) return false;
    return figure.getFigureCollision(root);
  }

  // -------------------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------------------

  /// Sets the playback FPS. FPS only affects how fast frames are played; it
  /// never rescales keyframes, the timeline length, or the total frame count.
  void setFps(double f) {
    final newFps = f.clamp(1, 60).toDouble();
    fps = newFps;
    figure.fps = newFps;
    forceUpdate();
  }

  void setDuration(double d) {
    _duration = d < 0 ? 0 : d;
    if (currentAnimation != null) {
      currentAnimation!.duration = _duration;
    }
    forceUpdate();
  }

  void setCurrentTime(double t, {bool notify = true}) {
    currentTime = t.clamp(0.0, duration <= 0 ? 0 : duration);
    if (notify) notifyListeners();
  }

  void setCurrentAnimation(FigureAnimation? a) {
    currentAnimation = a;
    if (a != null && a.duration > 0) {
      _duration = a.duration;
    } else if (currentAnimation != null) {
      currentAnimation!.duration = _duration;
    }
    forceUpdate();
  }

  void togglePlay() {
    if (isPlaying) {
      stopPlayback();
    } else {
      startPlayback();
    }
  }

  void startPlayback() {
    if (duration <= 0) return;
    isPlaying = true;
    notifyListeners();
    _playbackTimer?.cancel();
    final startT = currentTime;
    final startWall = DateTime.now();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final elapsed = DateTime.now().difference(startWall).inMicroseconds / 1e6;
      // FPS translates wall-clock elapsed time into frames; the stored
      // timeline itself is fps-independent.
      var t = (startT + elapsed * fps) % duration;
      _applyAnimationAt(t);
    });
  }

  void stopPlayback() {
    isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    notifyListeners();
  }

  void stepFrame(int delta) {
    var frame = currentFrame + delta;
    var t = frame.toDouble();
    if (t >= duration && frame >= totalFrames) {
      if (duration > 0) {
        frame = 0;
        t = 0;
      }
    }
    _applyAnimationAt(t);
  }

  void _applyAnimationAt(double t) {
    if (currentAnimation == null) {
      currentTime = t;
      notifyListeners();
      return;
    }
    final wasNull = _savedPoints == null;
    if (wasNull) {
      _savedPoints = figure.points.map((p) => p.clone()).toList();
    }
    currentAnimation!.applyToFigure(figure, t, autoEasing);
    currentTime = t;
    // Bake the visited frame so later edits elsewhere don't leak into it.
    if (!isPlaying && isAnimateMode) {
      final frame = t.roundToDouble();
      for (final track in currentAnimation!.tracks) {
        final i = track.pointIndex;
        if (i < 0 || i >= figure.points.length) continue;
        final p = figure.points[i];
        track.addKeyframe(frame, p.x, p.y);
      }
    }
    notifyListeners();
  }

  /// Bakes all point tracks and frame properties across the full duration so
  /// every integer frame has an explicit state.
  void bakeAllFrames() {
    if (!isAnimateMode) return;
    final anim = currentAnimation;
    final last = duration.floor();
    if (anim != null) {
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        for (final track in anim.tracks) {
          final i = track.pointIndex;
          if (i < 0 || i >= figure.points.length) continue;
          final exists = track.keyframes.any(
            (kf) => (kf.time - t).abs() < 0.001,
          );
          if (exists) continue;
          final val = track.getValue(t, autoEasing);
          if (val != null) {
            track.addKeyframe(t, val.x, val.y);
          } else {
            final base = (i < (_savedPoints?.length ?? 0))
                ? _savedPoints![i]
                : figure.points[i];
            track.addKeyframe(t, base.x, base.y);
          }
        }
      }
    }

    // Bake figure-level keyframe tracks.
    for (final key in figure.visibility.keys.toList()) {
      final root = int.tryParse(key);
      if (root == null) continue;
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final track = figure.visibility[key];
        if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
          continue;
        }
        figure.setFigureVisibility(
          root,
          t,
          figure.getFigureVisibility(root, t),
        );
      }
    }
    for (final key in figure.opacity.keys.toList()) {
      final root = int.tryParse(key);
      if (root == null) continue;
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final track = figure.opacity[key];
        if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
          continue;
        }
        figure.setFigureOpacity(root, t, figure.getFigureOpacity(root, t));
      }
    }
    for (final key in figure.colors.keys.toList()) {
      final root = int.tryParse(key);
      if (root == null) continue;
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final track = figure.colors[key];
        if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
          continue;
        }
        final val = figure.getFigureColorOverride(root, t);
        if (val != null) figure.setFigureColorOverride(root, t, val);
      }
    }
    for (final segId in figure.segmentImages.keys.toList()) {
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final track = figure.segmentImages[segId];
        if (track != null && track.any((kf) => (kf.time - t).abs() < 0.001)) {
          continue;
        }
        final val = figure.getSegmentImageIndex(segId, t);
        if (val != null) figure.setSegmentImageIndex(segId, t, val);
      }
    }

    // Bake known frame override keys.
    final overrideKeys = <String>{};
    for (final values in figure.frameOverrides.values) {
      overrideKeys.addAll(values.keys.map((k) => k.toString()));
    }
    for (final key in overrideKeys) {
      for (var f = 0; f <= last; f++) {
        final t = f.toDouble();
        final frame = figure.frameOverrides[t];
        if (frame != null && frame.containsKey(key)) continue;
        final resolved = figure.frameObject(key, t, null);
        figure.frameOverrides.putIfAbsent(t, () => <String, dynamic>{})[key] =
            resolved;
      }
    }
  }

  /// Applies the animation pose at the current time (used by the transport
  /// prev/next controls).
  void applyPose() {
    if (!isAnimateMode || currentAnimation == null) return;
    _applyAnimationAt(currentTime);
  }

  // -------------------------------------------------------------------------
  // Frame clipboard (copy / paste / delete a whole frame)
  // -------------------------------------------------------------------------

  Map<int, Point2>? _copiedFrame;

  bool get hasCopiedFrame => _copiedFrame != null && _copiedFrame!.isNotEmpty;

  /// Captures the interpolated pose at [t] for every animated point.
  void copyFrame(double t) {
    final anim = currentAnimation;
    if (anim == null) return;
    final snap = <int, Point2>{};
    for (final track in anim.tracks) {
      if (track.pointIndex < 0 || track.pointIndex >= figure.points.length) {
        continue;
      }
      final kf = track.getValue(t, autoEasing);
      if (kf != null) snap[track.pointIndex] = Point2(kf.x, kf.y);
    }
    _copiedFrame = snap;
    notifyListeners();
  }

  /// Pastes the copied pose as keyframes at [t].
  void pasteFrame(double t) {
    final anim = currentAnimation;
    final snap = _copiedFrame;
    if (anim == null || snap == null || snap.isEmpty) return;
    final times = authoredFrameTimes()..add(t.roundToDouble());
    for (final e in snap.entries) {
      recordPointPose(
        e.key,
        e.value.x,
        e.value.y,
        authoredTimes: times,
        time: t,
      );
    }
    if (anim.duration < t + 1) anim.duration = t + 1;
    forceUpdate();
    applyPose();
  }

  /// Removes the keyframes at [t] for all tracks (deletes the frame).
  void deleteFrame(double t) {
    final anim = currentAnimation;
    if (anim == null) return;
    for (final track in anim.tracks) {
      track.removeKeyframe(t);
    }
    anim.tracks.removeWhere((tr) => tr.keyframes.isEmpty);
    forceUpdate();
    applyPose();
  }

  /// Builds a clean snapshot of the figure posed at [t] (rest-pose base),
  /// used for frame thumbnails.
  Figure thumbnailFigure(double t) {
    final fig = figure.clone();
    if (_savedPoints != null) {
      for (var i = 0; i < fig.points.length && i < _savedPoints!.length; i++) {
        fig.points[i] = _savedPoints![i].clone();
      }
    }
    currentAnimation?.applyToFigure(fig, t, autoEasing);
    return fig;
  }

  /// Enters animate mode: snapshot original point positions.
  void enterAnimateMode() {
    if (_savedPoints == null && _figure != null) {
      _savedPoints = figure.points.map((p) => p.clone()).toList();
    }
    _applyAnimationAt(currentTime);
  }

  /// Leaves animate mode: restore original point positions.
  void leaveAnimateMode() {
    stopPlayback();
    if (_savedPoints != null && _figure != null) {
      for (
        var i = 0;
        i < figure.points.length && i < _savedPoints!.length;
        i++
      ) {
        figure.points[i].x = _savedPoints![i].x;
        figure.points[i].y = _savedPoints![i].y;
      }
      _savedPoints = null;
    }
    notifyListeners();
  }

  /// Records the dragged pose of [pointIndex] at [currentTime] as a keyframe.
  void recordPose(int pointIndex, {Set<double>? authoredTimes}) {
    if (!isAnimateMode || _figure == null) return;
    if (pointIndex < 0 || pointIndex >= figure.points.length) return;
    final pt = figure.points[pointIndex];
    recordPointPose(pointIndex, pt.x, pt.y, authoredTimes: authoredTimes);
  }

  /// Creates an animation if none exists and returns it.
  FigureAnimation ensureAnimation() {
    if (currentAnimation == null) {
      currentAnimation = FigureAnimation('Animation');
      currentAnimation!.duration = _duration;
      notifyListeners();
    }
    return currentAnimation!;
  }

  /// Captures the current figure positions for all dragged points.
  void recordPosesForIndices(List<int> indices) {
    if (!isAnimateMode) return;
    final times = authoredFrameTimes();
    for (final i in indices) {
      recordPose(i, authoredTimes: times);
    }
    forceUpdate();
  }

  // -------------------------------------------------------------------------
  // Animation settings toggles
  // -------------------------------------------------------------------------

  void setOnionPrev(bool v) {
    onionPrev = v;
    notifyListeners();
  }

  void setOnionNext(bool v) {
    onionNext = v;
    notifyListeners();
  }

  void setAutoEasing(bool v) {
    autoEasing = v;
    notifyListeners();
  }

  void setCanvasSize(double w, double h) {
    figure.canvasWidth = w.clamp(100, 10000);
    figure.canvasHeight = h.clamp(100, 10000);
    pushHistory();
    forceUpdate();
  }

  /// Scales all points of the figure about the first root (root point stays
  /// fixed) by [percent] (100 = unchanged). Registers undo history.
  void scaleAll(double percent) {
    final f = figure;
    if (f.points.isEmpty) return;
    final factor = (percent.clamp(1, 1000)) / 100.0;
    final roots = f.getFigureRoots();
    final cx = roots.isNotEmpty && roots.first < f.points.length
        ? f.points[roots.first].x
        : f.canvasWidth / 2;
    final cy = roots.isNotEmpty && roots.first < f.points.length
        ? f.points[roots.first].y
        : f.canvasHeight / 2;
    for (final p in f.points) {
      p.x = cx + (p.x - cx) * factor;
      p.y = cy + (p.y - cy) * factor;
    }
    recordPointsAtCurrentFrame(List<int>.generate(f.points.length, (i) => i));
    pushHistory();
    forceUpdate();
  }

  void setCanvasColor(String hex) {
    figure.canvasColor = hex;
    pushHistory();
    forceUpdate();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
