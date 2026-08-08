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

  const CameraTransform({
    this.x = 0,
    this.y = 0,
    this.zoom = 0.8,
  });

  CameraTransform copyWith({double? x, double? y, double? zoom}) =>
      CameraTransform(x: x ?? this.x, y: y ?? this.y, zoom: zoom ?? this.zoom);
}

/// Central editor state, the Flutter analog of `FigureEditorContext.tsx`.
class EditorController extends ChangeNotifier {
  static const int maxHistory = 50;

  String? projectId;

  Figure? _figure;
  Figure get figure => _figure!;

  String? selectedSegmentId;
  int? selectedPointIndex;
  final Map<int, String> pointModes = {}; // index -> 'dynamic' | 'static'

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
  bool showConnectors = true;

  /// The image segment currently being edited in asset mode (by id).
  String? assetSegmentId;

  void toggleConnectors() {
    showConnectors = !showConnectors;
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

  double get frameDuration => 1.0 / fps;
  int get totalFrames =>
      duration <= 0 ? 1 : (duration * fps).round().clamp(1, 1000000);
  int get currentFrame => (currentTime * fps).round().clamp(0, totalFrames - 1);

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  static Future<EditorController> load({
    required EditorMode mode,
    String? projectId,
  }) async {
    var figure = Figure();
    FigureAnimation? anim;

    if (projectId != null) {
      final meta = await ProjectStorage.getProject(projectId);
      if (meta != null) figure.name = meta.name;
      final data = await ProjectStorage.loadProjectData(projectId);
      if (data != null) {
        if (data.figure != null) {
          final parsed = Figure.fromJsonString(data.figure!);
          if (parsed.segments.isNotEmpty) figure = parsed;
        }
        if (data.animation != null) {
          anim = FigureAnimation.fromJsonString(data.animation!);
        }
      }
    }

    final controller = EditorController(
      editorMode: mode,
      projectId: projectId,
      initialFigure: figure,
      initialAnimation: anim,
    );
    controller.loaded = true;
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
    } else {
      pointModes[index] = 'static';
    }
    notifyListeners();
  }

  bool isPointStatic(int index) => pointModes[index] == 'static';

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
    forceUpdate();
    pushHistory();
    return root;
  }

  /// Merges the dragged point into [targetIdx]; the surviving (target) root
  /// is kept and the moved point's root is dropped.
  void joinPoints(int movedIdx, int targetIdx) {
    if (_figure == null) return;
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
    if (currentAnimation != null) {
      currentAnimation!.tracks.removeWhere((t) => t.pointIndex == movedIdx);
      for (final t in currentAnimation!.tracks) {
        if (t.pointIndex > movedIdx) t.pointIndex--;
      }
    }
    forceUpdate();
    pushHistory();
  }

  /// Splits the joint point so it detaches from [detachFromIdx], giving the
  /// detached segment its own root at [copyX],[copyY].
  void splitJoint(int ptIdx, int detachFromIdx, double copyX, double copyY) {
    if (_figure == null) return;
    final newIdx = _figure!.splitJoint(ptIdx, detachFromIdx, copyX, copyY);
    if (newIdx < 0) return;
    setSelectedPoint(ptIdx);
    pushHistory();
    forceUpdate();
  }

  // -------------------------------------------------------------------------
  // Layer groups
  // -------------------------------------------------------------------------

  /// Creates a new, empty layer group.
  void addLayerGroup({String? name}) {
    if (_figure == null) return;
    _figure!.groups.add(LayerGroup(
      id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
      name: name ?? 'Group ${_figure!.groups.length}',
    ));
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
  String groupOf(String segId) => _figure?.groupOf(segId) ?? Figure.defaultGroupId;

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
    final comp = figure.connectedComponent(ptIdx);
    final root = figure.rootIndices.firstWhere(
      (r) => comp.contains(r),
      orElse: () => -1,
    );
    if (root == -1) return;

    final isVisible = figure.getFigureVisibility(root, currentTime);
    figure.setFigureVisibility(root, currentTime, !isVisible);
    
    pushHistory();
    forceUpdate();
  }

  void setFigureOpacity(int ptIdx, double val) {
    if (_figure == null) return;
    final comp = figure.connectedComponent(ptIdx);
    final root = figure.rootIndices.firstWhere(
      (r) => comp.contains(r),
      orElse: () => -1,
    );
    if (root == -1) return;

    figure.setFigureOpacity(root, currentTime, val);
    
    pushHistory();
    forceUpdate();
  }

  // -------------------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------------------

  void setFps(double f) {
    final newFps = f.clamp(1, 60).toDouble();
    final prevTotal = totalFrames;
    fps = newFps;
    figure.fps = newFps;
    if (_duration > 0) {
      final newDuration = prevTotal / newFps;
      _duration = newDuration;
      if (currentAnimation != null && currentAnimation!.duration > 0) {
        currentAnimation!.duration = newDuration;
      }
    }
    forceUpdate();
  }

  void setDuration(double d) {
    _duration = d < 0 ? 0 : d;
    forceUpdate();
  }

  void setCurrentTime(double t, {bool notify = true}) {
    currentTime = t.clamp(0.0, duration <= 0 ? 0 : duration);
    if (notify) notifyListeners();
  }

  void setCurrentAnimation(FigureAnimation? a) {
    currentAnimation = a;
    if (a != null && a.duration > 0) _duration = a.duration;
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
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        final elapsed =
            DateTime.now().difference(startWall).inMicroseconds / 1e6;
        var t = (startT + elapsed) % duration;
        _applyAnimationAt(t);
      },
    );
  }

  void stopPlayback() {
    isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    notifyListeners();
  }

  void stepFrame(int delta) {
    var frame = currentFrame + delta;
    var t = frame * frameDuration;
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
    notifyListeners();
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
    for (final e in snap.entries) {
      final track = anim.getOrCreateTrack(e.key);
      track.addKeyframe(t, e.value.x, e.value.y);
    }
    if (anim.duration < t) anim.duration = t;
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
      for (var i = 0; i < figure.points.length && i < _savedPoints!.length; i++) {
        figure.points[i].x = _savedPoints![i].x;
        figure.points[i].y = _savedPoints![i].y;
      }
      _savedPoints = null;
    }
    notifyListeners();
  }

  /// Records the dragged pose of [pointIndex] at [currentTime] as a keyframe.
  void recordPose(int pointIndex) {
    if (!isAnimateMode || _figure == null) return;
    if (pointIndex < 0 || pointIndex >= figure.points.length) return;
    final anim = ensureAnimation();
    final pt = figure.points[pointIndex];
    anim.setPointPose(currentTime, pointIndex, pt.x, pt.y);
    if (anim.duration > _duration) {
      _duration = anim.duration;
    }
  }

  /// Creates an animation if none exists and returns it.
  FigureAnimation ensureAnimation() {
    if (currentAnimation == null) {
      currentAnimation = FigureAnimation('Animation');
      notifyListeners();
    }
    return currentAnimation!;
  }

  /// Captures the current figure positions for all dragged points.
  void recordPosesForIndices(List<int> indices) {
    for (final i in indices) {
      recordPose(i);
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
