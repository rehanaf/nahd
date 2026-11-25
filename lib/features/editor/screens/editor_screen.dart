import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../core/widgets/color_picker_sheet.dart';

import '../../../core/lottie_export.dart';
import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';
import '../../../core/pose_library.dart';
import '../../../core/project_storage.dart';
import '../../../core/render/figure_render.dart';
import '../controllers/editor_controller.dart';
import '../controllers/editor_controller_svg_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/animation_settings_panel.dart';
import '../widgets/animation_transport.dart';
import '../widgets/editor_buttons.dart';
import '../widgets/figure_canvas.dart';
import '../widgets/layer_panel.dart';
import '../widgets/segment_inspector.dart';
import '../widgets/frames_screen.dart';

part 'editor_screen_sheets.dart';

/// Single accent colour used by every editor tool button for a unified look.
const Color kToolColor = Color(0xFF2563EB);

class EditorScreen extends StatefulWidget {
  final EditorController controller;
  final VoidCallback onBack;

  const EditorScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _RightTab { settings, inspector, layers }

class _EditorScreenState extends State<EditorScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _RightTab? _rightTab;
  bool _showMenu = false;

  String _lastModifyKey = 'point';
  String _lastTransformKey = 'moveAll';
  int _sideTab = 0; // 0 = drawing/segment, 1 = utility

  //--------------------------------------------------------------------------
  // Actions
  //--------------------------------------------------------------------------

  void _handleFlip() {
    final c = widget.controller;
    final segId = c.selectedSegmentId;
    if (segId == null) return;
    final seg = c.figure.getSegment(segId);
    if (seg == null) return;
    if (seg.point1Index >= c.figure.points.length ||
        seg.point2Index >= c.figure.points.length) {
      return;
    }
    final p1 = c.figure.points[seg.point1Index];
    final p2 = c.figure.points[seg.point2Index];
    p1.x = 2 * p2.x - p1.x;
    c.forceUpdate();
    c.pushHistory();
  }

  void _layerUp() {
    final c = widget.controller;
    final segId = c.selectedSegmentId;
    if (segId == null) return;
    final seg = c.figure.getSegment(segId);
    if (seg == null) return;
    seg.layer = seg.layer + 1;
    c.forceUpdate();
    c.pushHistory();
  }

  /// Modify group: point/modify/curve mapping to selection keys.
  bool _isModifyTool(EditorTool t) =>
      t == EditorTool.point || t == EditorTool.modify || t == EditorTool.curve;

  String _modifyKey(EditorTool t) {
    if (_isModifyTool(t)) {
      _lastModifyKey = switch (t) {
        EditorTool.modify => 'modify',
        EditorTool.curve => 'curve',
        _ => 'point',
      };
    }
    print("Mapper _modifyKey activeTool: $t, returning $_lastModifyKey");
    return _lastModifyKey;
  }

  EditorTool _modifyTool(String key) => switch (key) {
    'modify' => EditorTool.modify,
    'curve' => EditorTool.curve,
    _ => EditorTool.point,
  };

  /// Transform group: move all / rotate all / scale all mapping.
  bool _isTransformTool(EditorTool t) =>
      t == EditorTool.select ||
      t == EditorTool.rotateAll ||
      t == EditorTool.stretch;

  String _transformKey(EditorTool t) {
    if (_isTransformTool(t)) {
      _lastTransformKey = switch (t) {
        EditorTool.rotateAll => 'rotateAll',
        EditorTool.stretch => 'scaleAll',
        _ => 'moveAll',
      };
    }
    print("Mapper _transformKey activeTool: $t, returning $_lastTransformKey");
    return _lastTransformKey;
  }

  EditorTool _transformTool(String key) => switch (key) {
    'rotateAll' => EditorTool.rotateAll,
    'scaleAll' => EditorTool.stretch,
    _ => EditorTool.select,
  };

  void _layerDown() {
    final c = widget.controller;
    final segId = c.selectedSegmentId;
    if (segId == null) return;
    final seg = c.figure.getSegment(segId);
    if (seg == null) return;
    seg.layer = seg.layer > 0 ? seg.layer - 1 : 0;
    c.forceUpdate();
    c.pushHistory();
  }

  void _handleReset() {
    final c = widget.controller;
    final f = Figure();
    if (c.isAnimateMode) f.points = [];
    c.setFigure(f);
    c.setSelectedSegment(null);
    c.setSelectedPoint(null);
    c.pointModes.clear();
    c.forceUpdate();
  }

  Future<void> _handleAddFigure(ProjectMeta meta) async {
    final c = widget.controller;
    try {
      final data = await ProjectStorage.loadProjectData(meta.id);
      if (data?.figure == null) return;
      final src = Figure.fromJsonString(data!.figure!);
      if (src.points.isEmpty) return;

      final srcPts = src.points;
      final offsetX = 0.0;
      final offsetY = 0.0;

      final indexMap = <int, int>{};
      final base = c.figure.points.length;
      for (var i = 0; i < srcPts.length; i++) {
        indexMap[i] = base + i;
        c.figure.points.add(
          Point2(srcPts[i].x + offsetX, srcPts[i].y + offsetY),
        );
      }
      final roots = c.figure.rootIndices;
      final newRoots = <int>[];
      for (final r in src.rootIndices) {
        final mapped = indexMap[r];
        if (mapped == null) continue;
        newRoots.add(mapped);
        if (!roots.contains(mapped)) roots.add(mapped);
      }
      if (c.isAnimateMode) {
        final authoredTimes = c.authoredFrameTimes();
        for (final r in newRoots) {
          final t = c.currentTime.roundToDouble();
          c.figure.setFigureVisibility(r, 0.0, false);
          if (t > 0.001) {
            c.figure.setFigureVisibility(
              r,
              t,
              true,
              authoredTimes: authoredTimes,
            );
          } else {
            c.figure.setFigureVisibility(r, 0.0, true);
            final next = authoredTimes
                .where((at) => at.roundToDouble() > 0.0)
                .fold<double?>(null, (p, at) {
                  final rt = at.roundToDouble();
                  return p == null || rt < p ? rt : p;
                });
            if (next != null) {
              c.figure.visibility
                  .putIfAbsent(r.toString(), () => [])
                  .removeWhere((kf) => (kf.time - next).abs() < 0.001);
              c.figure.visibility[r.toString()]!.add(
                VisibilityKeyframe(next, false),
              );
              c.figure.visibility[r.toString()]!.sort(
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
        // A pasted figure/preset must not share segment ids with the source
        // project; per-frame overrides are keyed by id, so give it fresh ones.
        final newId = Segment(ns.type).id;
        segIdMap[s.id] = newId;
        ns.id = newId;
        ns.point1Index = p1;
        ns.point2Index = p2;
        ns.layer = (ns.layer) + c.figure.segments.length;
        c.figure.segments.add(ns);
      }
      src.remappedAttachedSegments(segIdMap, indexMap).forEach((joint, ids) {
        c.figure.attachedSegments[joint] = ids;
      });
      src.cycleFills.forEach((key, entry) {
        final parts = key
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toList();
        if (parts.length < 2) return;
        final mapped = parts.map((p) => indexMap[p]).whereType<int>().toList();
        if (mapped.length != parts.length) return;
        mapped.sort();
        c.figure.cycleFills[mapped.join(',')] = entry.clone();
      });
      String? remapOverrideKey(String key) {
        final parts = key.split(':');
        if (parts.length >= 3 && parts[0] == 'seg') {
          final newId = segIdMap[parts[1]];
          if (newId == null) return null;
          return ['seg', newId, ...parts.skip(2)].join(':');
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
          final newKey = remapOverrideKey(key.toString());
          if (newKey != null) mapped[newKey] = value;
        });
        if (mapped.isNotEmpty) {
          c.figure.frameOverrides[frame] = Map<String, dynamic>.from(
            c.figure.frameOverrides[frame] ?? {},
          )..addAll(mapped);
        }
      });
      c.recordPointsAtCurrentFrame(indexMap.values);
      c.mergeGroupsFrom(src, segIdMap);
      c.forceUpdate();
      c.pushHistory();
    } catch (_) {
      // ignore
    }
  }

  void _showSnack(String message) {
    final palette = Theme.of(context).appColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: palette.text)),
        backgroundColor: palette.backgroundElement,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openRightTab(_RightTab tab) {
    setState(() => _rightTab = tab);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Future<void> _pickAndAddImageSegment(EditorController c) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      String ext = result.files.first.extension ?? 'png';
      if (ext == 'jpg') ext = 'jpeg';
      final base64Str = 'data:image/$ext;base64,${base64Encode(bytes)}';
      c.addSegmentWithImage(base64Str);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gagal memilih gambar')));
      }
    }
  }

  Widget _buildLeftDrawer(EditorController c, AppPalette palette) {
    return Drawer(
      width: 300,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
      ),
      backgroundColor: palette.backgroundElement,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Add Asset / Segment",
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  color: palette.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              "ADD SEGMENT",
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _drawerSegmentIcon(
                  icon: LucideIcons.pencil,
                  label: 'Line',
                  color: kToolColor,
                  onTap: () {
                    c.addSegment('line');
                    Navigator.of(context).pop();
                  },
                  palette: palette,
                ),
                _drawerSegmentIcon(
                  icon: LucideIcons.circle,
                  label: 'Circle',
                  color: kToolColor,
                  onTap: () {
                    c.addSegment('circle');
                    Navigator.of(context).pop();
                  },
                  palette: palette,
                ),
                _drawerSegmentIcon(
                  icon: LucideIcons.image,
                  label: 'Image',
                  color: kToolColor,
                  onTap: () => _pickAndAddImageSegment(c),
                  palette: palette,
                ),
              ],
            ),
          ),
          const Divider(height: 24, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              c.isAnimateMode
                  ? "ADD FIGURE / PRESET ASSET"
                  : "ADD FIGURE ASSET",
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                ProjectStorage.listGroups(ProjectType.figure),
                ProjectStorage.listProjects(ProjectType.figure),
                ProjectStorage.listGroups(ProjectType.preset),
                ProjectStorage.listProjects(ProjectType.preset),
              ]),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data ?? [[], [], [], []];
                final figureGroups = List<ProjectGroup>.from(data[0] as List);
                final groups = <ProjectGroup>[
                  ...figureGroups,
                  ...List<ProjectGroup>.from(
                    data[2] as List,
                  ).where((g) => !figureGroups.any((f) => f.id == g.id)),
                ];
                final projects = <ProjectMeta>[
                  ...List<ProjectMeta>.from(data[1] as List),
                  // Animation (and Preset) scenes can re-create objects by
                  // importing a preset at the current frame.
                  if (c.isAnimateMode)
                    ...List<ProjectMeta>.from(data[3] as List),
                ];
                final filtered = projects
                    .where((p) => p.id != c.projectId)
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        c.isAnimateMode
                            ? "No figures or presets found"
                            : "No other figures found",
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                final grouped = <String?, List<ProjectMeta>>{};
                for (final p in filtered) {
                  grouped.putIfAbsent(p.groupId, () => []).add(p);
                }

                final displayGroups = <Widget>[];

                for (final group in groups) {
                  final groupProjects = grouped[group.id] ?? [];
                  if (groupProjects.isEmpty) continue;
                  displayGroups.add(
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          group.name,
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        leading: Icon(
                          LucideIcons.folder,
                          color: palette.textSecondary,
                          size: 18,
                        ),
                        childrenPadding: const EdgeInsets.only(left: 16),
                        initiallyExpanded: true,
                        children: groupProjects
                            .map((p) => _buildFigureListTile(p, palette))
                            .toList(),
                      ),
                    ),
                  );
                }

                final activeGroupIds = groups.map((g) => g.id).toSet();
                final ungroupedProjects = filtered
                    .where(
                      (p) =>
                          p.groupId == null ||
                          !activeGroupIds.contains(p.groupId),
                    )
                    .toList();
                if (ungroupedProjects.isNotEmpty) {
                  displayGroups.add(
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          "Default / Ungrouped",
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        leading: Icon(
                          LucideIcons.folder_open,
                          color: palette.textSecondary,
                          size: 18,
                        ),
                        childrenPadding: const EdgeInsets.only(left: 16),
                        initiallyExpanded: true,
                        children: ungroupedProjects
                            .map((p) => _buildFigureListTile(p, palette))
                            .toList(),
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: displayGroups,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFigureListTile(ProjectMeta meta, AppPalette palette) {
    return Card(
      color: palette.background,
      margin: const EdgeInsets.only(bottom: 8, right: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.border, width: 0.5),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          meta.name,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${meta.type == ProjectType.preset ? 'Preset' : 'Figure'} · "
          "ID: ${meta.id.substring(0, math.min(8, meta.id.length))}...",
          style: TextStyle(color: palette.textSecondary, fontSize: 11),
        ),
        trailing: Icon(LucideIcons.plus, color: palette.text, size: 16),
        onTap: () {
          _handleAddFigure(meta);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _drawerSegmentIcon({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required AppPalette palette,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OverlayCapsule(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 36,
            height: 36,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: palette.textSecondary, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildDrawer(EditorController c, AppPalette palette) {
    final tab = _rightTab ?? _RightTab.inspector;
    return Drawer(
      width: 300,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
      ),
      backgroundColor: palette.backgroundElement,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tab == _RightTab.inspector
                        ? "Properties"
                        : tab == _RightTab.settings
                        ? "Animation Settings"
                        : "Layers",
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  color: palette.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (tab) {
              _RightTab.inspector => SegmentInspector(controller: c),
              _RightTab.settings => AnimationSettingsPanel(controller: c),
              _RightTab.layers => LayerPanel(controller: c),
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final palette = Theme.of(context).appColors;
        final canFlip =
            c.selectedSegmentId != null &&
            c.figure.getSegment(c.selectedSegmentId!) != null;
        return _buildScaffold(context, c, palette, canFlip);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    EditorController c,
    AppPalette palette,
    bool canFlip,
  ) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: palette.background,
      drawer: _buildLeftDrawer(c, palette),
      endDrawer: _buildDrawer(c, palette),
      onEndDrawerChanged: (opened) {
        if (!opened && _rightTab != null) {
          setState(() => _rightTab = null);
        }
      },
      body: Stack(
        children: [
          Positioned.fill(child: FigureCanvas(controller: c)),

          // Top unified bar (Back button, Undo/Redo, Tool Mode capsule, Animation Transport, and More menu).
          Positioned(
            top: 4 + pad.top,
            left: 4 + pad.left,
            right: 4 + pad.right,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Back + Undo/Redo.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OverlayCapsule(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: InkWell(
                          onTap: widget.onBack,
                          borderRadius: BorderRadius.circular(16),
                          child: Icon(
                            LucideIcons.arrow_left,
                            size: 18,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OverlayCapsule(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          EditorIconButton(
                            icon: LucideIcons.undo,
                            disabled: !c.canUndo,
                            onTap: c.undo,
                          ),
                          const SizedBox(width: 4),
                          EditorIconButton(
                            icon: LucideIcons.redo,
                            disabled: !c.canRedo,
                            onTap: c.redo,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    OverlayCapsule(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          EditorIconButton(
                            icon: LucideIcons.folder_plus,
                            color: kToolColor,
                            onTap: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          ),
                          const SizedBox(width: 4),
                          EditorIconButton(
                            icon: LucideIcons.hand,
                            color: kToolColor,
                            active: c.panEnabled,
                            onTap: c.togglePanEnabled,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Center: Tool mode capsule.
                OverlayCapsule(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pivot (default active).
                      EditorIconButton(
                        icon: LucideIcons.rotate_cw,
                        color: kToolColor,
                        active: c.activeTool == EditorTool.rotate,
                        onTap: () => c.setTool(EditorTool.rotate),
                      ),
                      const SizedBox(width: 4),
                      // Modify group (Point, Modify, Curve).
                      ToolGroupButton(
                        subTools: const [
                          ToolGroupSub(
                            icon: LucideIcons.move,
                            key: 'point',
                            color: kToolColor,
                          ),
                          ToolGroupSub(
                            icon: LucideIcons.focus,
                            key: 'modify',
                            color: kToolColor,
                          ),
                          ToolGroupSub(
                            icon: LucideIcons.timeline,
                            key: 'curve',
                            color: kToolColor,
                          ),
                        ],
                        selectedKey: _modifyKey(c.activeTool),
                        onSelect: (k) {
                          setState(() => _lastModifyKey = k);
                          c.setTool(_modifyTool(k));
                        },
                        active: _isModifyTool(c.activeTool),
                        onActivate: () =>
                            c.setTool(_modifyTool(_lastModifyKey)),
                        placement: ToolGroupPlacement.bottom,
                      ),
                      const SizedBox(width: 4),
                      // Transform group (Move All, Rotate All, Scale All).
                      ToolGroupButton(
                        subTools: const [
                          ToolGroupSub(
                            icon: LucideIcons.navigation,
                            key: 'moveAll',
                            color: kToolColor,
                          ),
                          ToolGroupSub(
                            icon: LucideIcons.rotate_ccw,
                            key: 'rotateAll',
                            color: kToolColor,
                          ),
                          ToolGroupSub(
                            icon: LucideIcons.minimize,
                            key: 'scaleAll',
                            color: kToolColor,
                          ),
                        ],
                        selectedKey: _transformKey(c.activeTool),
                        onSelect: (k) {
                          setState(() => _lastTransformKey = k);
                          c.setTool(_transformTool(k));
                        },
                        active: _isTransformTool(c.activeTool),
                        onActivate: () =>
                            c.setTool(_transformTool(_lastTransformKey)),
                        placement: ToolGroupPlacement.bottom,
                      ),
                    ],
                  ),
                ),

                // Right: Animation transport capsule (prev/next) OR Scene Mode capsule + More (zoom) menu.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isAnimateMode)
                      AnimationTransport(controller: c)
                    else
                      OverlayCapsule(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EditorIconButton(
                              icon: LucideIcons.accessibility,
                              color: kToolColor,
                              active: c.rigMode == RigMode.rig,
                              onTap: () => c.setRigMode(RigMode.rig),
                            ),
                            const SizedBox(width: 4),
                            EditorIconButton(
                              icon: LucideIcons.crop,
                              color: kToolColor,
                              active: c.rigMode == RigMode.asset,
                              onTap: () => c.setRigMode(RigMode.asset),
                            ),
                            const SizedBox(width: 4),
                            EditorIconButton(
                              icon: LucideIcons.anchor,
                              color: kToolColor,
                              active: c.rigMode == RigMode.anchor,
                              onTap: () => c.setRigMode(RigMode.anchor),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 4),
                    OverlayCapsule(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: InkWell(
                          onTap: () => setState(() => _showMenu = !_showMenu),
                          borderRadius: BorderRadius.circular(16),
                          child: Icon(
                            LucideIcons.ellipsis,
                            size: 18,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Left sidebar — 5-tab system (Figure) or 1-capsule system (Animate/Preset)
          Positioned(
            top: 50 + pad.top,
            left: 4 + pad.left,
            child: c.isAnimateMode
                ? OverlayCapsule(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      width: 72,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Tooltip(
                            message: 'Permanent Delete',
                            child: EditorIconButton(
                              icon: LucideIcons.trash,
                              color: kToolColor,
                              disabled:
                                  c.selectedPointIndex == null &&
                                  c.selectedSegmentId == null,
                              onTap: () {
                                final ptIdx =
                                    c.selectedPointIndex ??
                                    (c.selectedSegmentId != null
                                        ? c.figure
                                              .getSegment(c.selectedSegmentId!)
                                              ?.point1Index
                                        : null);
                                if (ptIdx != null) {
                                  final comp = c.figure.connectedComponent(
                                    ptIdx,
                                  );
                                  final root = c.figure.rootIndices.firstWhere(
                                    (r) => comp.contains(r),
                                    orElse: () => -1,
                                  );
                                  if (root != -1) {
                                    c.removeFigureAt(root);
                                  }
                                }
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Attach Figure',
                            child: EditorIconButton(
                              icon: LucideIcons.link,
                              color: kToolColor,
                              active: c.activeTool == EditorTool.attach,
                              onTap: () {
                                c.setTool(
                                  c.activeTool == EditorTool.attach
                                      ? EditorTool.rotate
                                      : EditorTool.attach,
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            height: 1,
                            child: Center(
                              child: Container(
                                height: 1,
                                width: 48,
                                color: palette.border,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Center Figure',
                            child: EditorIconButton(
                              icon: LucideIcons.focus,
                              color: kToolColor,
                              disabled:
                                  c.selectedPointIndex == null &&
                                  c.selectedSegmentId == null,
                              onTap: () {
                                final ptIdx =
                                    c.selectedPointIndex ??
                                    (c.selectedSegmentId != null
                                        ? c.figure
                                              .getSegment(c.selectedSegmentId!)
                                              ?.point1Index
                                        : null);
                                if (ptIdx != null) {
                                  c.centerFigureAt(ptIdx);
                                }
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Toggle Visibility',
                            child: EditorIconButton(
                              icon: LucideIcons.eye,
                              color: kToolColor,
                              disabled:
                                  c.selectedPointIndex == null &&
                                  c.selectedSegmentId == null,
                              onTap: () {
                                final ptIdx = c.selectedFigurePoint();
                                if (ptIdx != null) {
                                  c.toggleFigureVisibility(ptIdx);
                                }
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Opacity',
                            child: EditorIconButton(
                              icon: LucideIcons.droplet,
                              color: kToolColor,
                              disabled:
                                  c.selectedPointIndex == null &&
                                  c.selectedSegmentId == null,
                              onTap: () {
                                final ptIdx = c.selectedFigurePoint();
                                if (ptIdx != null) {
                                  _showOpacitySlider(c, ptIdx);
                                }
                              },
                            ),
                          ),
                          Builder(
                            builder: (btnCtx) {
                              final ptIdx = c.selectedFigurePoint();
                              final hasSelection =
                                  ptIdx != null &&
                                  ptIdx >= 0 &&
                                  ptIdx < c.figure.points.length;
                              final cur = hasSelection
                                  ? c.figureColorOverrideAt(ptIdx)
                                  : null;
                              return Tooltip(
                                message: hasSelection
                                    ? (cur != null
                                          ? 'Figure Color (tap to change, long-press to clear)'
                                          : 'Figure Color')
                                    : 'Figure Color',
                                child: GestureDetector(
                                  onLongPress: hasSelection
                                      ? () => c.clearFigureColorOverride(ptIdx)
                                      : null,
                                  child: ColorCircle(
                                    color:
                                        parseHexColor(cur) ??
                                        const Color(0xFF8B5CF6),
                                    disabled: !hasSelection,
                                    onTap: hasSelection
                                        ? () async {
                                            final Color? picked =
                                                await showColorPickerSheet(
                                                  btnCtx,
                                                  parseHexColor(cur) ??
                                                      const Color(0xFF8B5CF6),
                                                );
                                            if (picked != null) {
                                              c.setFigureColorOverride(
                                                ptIdx,
                                                colorToHex(picked),
                                              );
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                          Builder(
                            builder: (btnCtx) {
                              final ptIdx = c.selectedFigurePoint();
                              final hasSelection =
                                  ptIdx != null &&
                                  ptIdx >= 0 &&
                                  ptIdx < c.figure.points.length;
                              final isCol =
                                  hasSelection && c.isFigureCollision(ptIdx);
                              return Tooltip(
                                message: hasSelection
                                    ? (isCol
                                          ? 'Collision: ON (tap to disable)'
                                          : 'Collision: OFF (tap to enable)')
                                    : 'Collision (select a figure)',
                                child: EditorIconButton(
                                  icon: LucideIcons.shield,
                                  color: kToolColor,
                                  active: isCol,
                                  disabled: !hasSelection,
                                  onTap: hasSelection
                                      ? () => c.toggleFigureCollision(ptIdx)
                                      : null,
                                ),
                              );
                            },
                          ),
                          Builder(
                            builder: (btnCtx) {
                              final seg = c.selectedSegmentId != null
                                  ? c.figure.getSegment(c.selectedSegmentId!)
                                  : null;
                              final isImg = seg != null && seg.type == 'image';
                              return Tooltip(
                                message: isImg
                                    ? 'Replace Image Asset'
                                    : 'Replace Image (select an image segment)',
                                child: EditorIconButton(
                                  icon: LucideIcons.image,
                                  color: kToolColor,
                                  disabled: !isImg,
                                  onTap: isImg
                                      ? () async {
                                          try {
                                            final result =
                                                await FilePicker.pickFiles(
                                                  type: FileType.image,
                                                  withData: true,
                                                );
                                            if (result != null &&
                                                result.files.isNotEmpty) {
                                              final bytes =
                                                  result.files.first.bytes;
                                              if (bytes != null) {
                                                final ext =
                                                    result
                                                        .files
                                                        .first
                                                        .extension ??
                                                    'png';
                                                final b64 = base64Encode(bytes);
                                                c.swapSegmentImage(
                                                  seg.id,
                                                  'data:image/$ext;base64,$b64',
                                                );
                                              }
                                            }
                                          } catch (err) {
                                            debugPrint(
                                              'Error replacing image: $err',
                                            );
                                          }
                                        }
                                      : null,
                                ),
                              );
                            },
                          ),
                          Builder(
                            builder: (btnCtx) {
                              final seg = c.selectedSegmentId != null
                                  ? c.figure.getSegment(c.selectedSegmentId!)
                                  : null;
                              final isSpriteImage =
                                  seg != null &&
                                  seg.type == 'image' &&
                                  seg.imageDataList.length > 1;
                              return Tooltip(
                                message: isSpriteImage
                                    ? 'Sprite Frame (tap to cycle)'
                                    : 'Sprite Frame (select an image segment)',
                                child: EditorIconButton(
                                  icon: LucideIcons.images,
                                  color: kToolColor,
                                  disabled: !isSpriteImage,
                                  onTap: isSpriteImage
                                      ? () {
                                          final curIdx =
                                              c.figure.getSegmentImageIndex(
                                                seg.id,
                                                c.currentTime,
                                              ) ??
                                              seg.activeImageIndex;
                                          final next =
                                              (curIdx + 1) %
                                              seg.imageDataList.length;
                                          c.selectSegmentImage(seg.id, next);
                                        }
                                      : null,
                                ),
                              );
                            },
                          ),
                          SizedBox(
                            width: 72,
                            height: 1,
                            child: Center(
                              child: Container(
                                height: 1,
                                width: 48,
                                color: palette.border,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Copy Pose',
                            child: EditorIconButton(
                              icon: LucideIcons.copy,
                              color: kToolColor,
                              onTap: () {
                                c.copyFrame(c.currentTime);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pose copied',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Color(0xFF22C55E),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Paste Pose',
                            child: EditorIconButton(
                              icon: LucideIcons.clipboard_paste,
                              color: kToolColor,
                              disabled: !c.hasCopiedFrame,
                              onTap: () {
                                c.pasteFrame(c.currentTime);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pose pasted',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Color(0xFF22C55E),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Capsule 1: Tab icons (always 5 tabs visible)
                      OverlayCapsule(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tab 0: Draw Tools
                            Tooltip(
                              message: 'Draw Tools',
                              child: EditorIconButton(
                                icon: LucideIcons.pencil,
                                color: kToolColor,
                                active: _sideTab == 0,
                                onTap: () => setState(() => _sideTab = 0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Tab 1: Type Tools
                            Tooltip(
                              message: 'Type Tools',
                              child: EditorIconButton(
                                icon: LucideIcons.layout_grid,
                                color: kToolColor,
                                active: _sideTab == 1,
                                onTap: () => setState(() => _sideTab = 1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Tab 2: Linejoin Tools
                            Tooltip(
                              message: 'Linejoin Tools',
                              child: EditorIconButton(
                                icon: LucideIcons.pen_tool,
                                color: kToolColor,
                                active: _sideTab == 2,
                                onTap: () => setState(() => _sideTab = 2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Tab 3: Appearance Tools
                            Tooltip(
                              message: 'Appearance',
                              child: EditorIconButton(
                                icon: LucideIcons.palette,
                                color: kToolColor,
                                active: _sideTab == 3,
                                onTap: () => setState(() => _sideTab = 3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Tab 4: Segment Tools
                            Tooltip(
                              message: 'Segment Tools',
                              child: EditorIconButton(
                                icon: LucideIcons.layers,
                                color: kToolColor,
                                active: _sideTab == 4,
                                onTap: () => setState(() => _sideTab = 4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Capsule 2: Content based on active tab
                      OverlayCapsule(
                        padding: const EdgeInsets.all(4),
                        child: Builder(
                          builder: (btnCtx) {
                            final activeTool = c.activeTool;
                            final seg = c.selectedSegmentId != null
                                ? c.figure.getSegment(c.selectedSegmentId!)
                                : null;

                            if (_sideTab == 0) {
                              // ── Tab 0: Draw Tools (s=switch) Line, Circle, Image, None ──
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Line Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.pencil,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.line,
                                      onTap: () {
                                        c.setTool(EditorTool.line);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Circle Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.circle,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.circle,
                                      onTap: () {
                                        c.setTool(EditorTool.circle);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Image Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.image,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.image,
                                      onTap: () {
                                        c.setTool(EditorTool.image);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Text Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.type,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.text,
                                      onTap: () {
                                        c.setTool(EditorTool.text);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'None Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.eye_off,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.none,
                                      onTap: () {
                                        c.setTool(EditorTool.none);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 1,
                                    width: 24,
                                    color: Theme.of(context).appColors.border,
                                  ),
                                  const SizedBox(height: 8),
                                  Tooltip(
                                    message: 'Join Tool',
                                    child: EditorIconButton(
                                      icon: LucideIcons.git_commit_vertical,
                                      color: kToolColor,
                                      active: activeTool == EditorTool.join,
                                      onTap: () {
                                        c.setTool(EditorTool.join);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              );
                            } else if (_sideTab == 1) {
                              // ── Tab 1: Type Tools (s=switch) change selected segment type ──
                              final segType = seg?.type ?? 'line';
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Type: Line',
                                    child: EditorIconButton(
                                      icon: LucideIcons.pencil,
                                      color: kToolColor,
                                      active: segType == 'line',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() {
                                          seg.type = 'line';
                                          seg.filled = true;
                                        });
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Type: Circle',
                                    child: EditorIconButton(
                                      icon: LucideIcons.circle,
                                      color: kToolColor,
                                      active: segType == 'circle',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() {
                                          seg.type = 'circle';
                                          seg.filled = false;
                                        });
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Type: Image',
                                    child: EditorIconButton(
                                      icon: LucideIcons.image,
                                      color: kToolColor,
                                      active: segType == 'image',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() {
                                          seg.type = 'image';
                                          seg.filled = true;
                                        });
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Type: Text',
                                    child: EditorIconButton(
                                      icon: LucideIcons.type,
                                      color: kToolColor,
                                      active: segType == 'text',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() {
                                          seg.type = 'text';
                                          seg.filled = false;
                                        });
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Type: None',
                                    child: EditorIconButton(
                                      icon: LucideIcons.eye_off,
                                      color: kToolColor,
                                      active: segType == 'none',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() {
                                          seg.type = 'none';
                                          seg.filled = false;
                                        });
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                ],
                              );
                            } else if (_sideTab == 2) {
                              // ── Tab 2: Linejoin Tools (s=switch) Round, Miter, Bevel ──
                              final cap = seg?.lineCap ?? 'round';
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Round',
                                    child: EditorIconButton(
                                      icon: LucideIcons.circle,
                                      color: kToolColor,
                                      active: cap == 'round',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() => seg.lineCap = 'round');
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Square',
                                    child: EditorIconButton(
                                      icon: LucideIcons.square,
                                      color: kToolColor,
                                      active: cap == 'square',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() => seg.lineCap = 'square');
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Butt',
                                    child: EditorIconButton(
                                      icon: LucideIcons.minus,
                                      color: kToolColor,
                                      active: cap == 'butt',
                                      disabled: seg == null,
                                      onTap: () {
                                        if (seg == null) return;
                                        setState(() => seg.lineCap = 'butt');
                                        c.forceUpdate();
                                        c.pushHistory();
                                      },
                                    ),
                                  ),
                                ],
                              );
                            } else if (_sideTab == 3) {
                              // ── Tab 3: Appearance Tools ──
                              // Collect cycle fills relevant to selected segment
                              final List<MapEntry<String, CycleFill>>
                              segCycles = [];
                              if (seg != null) {
                                c.figure.cycleFills.forEach((key, cf) {
                                  final pts = key
                                      .split(',')
                                      .map((p) => int.tryParse(p) ?? -1)
                                      .toList();
                                  if (pts.contains(seg.point1Index) &&
                                      pts.contains(seg.point2Index)) {
                                    segCycles.add(MapEntry(key, cf));
                                  }
                                });
                              }
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Image replace (if image type)
                                  if (seg != null && seg.type == 'image') ...[
                                    Tooltip(
                                      message: 'Replace Image',
                                      child: EditorIconButton(
                                        icon: LucideIcons.image,
                                        color: kToolColor,
                                        onTap: () async {
                                          try {
                                            final result =
                                                await FilePicker.pickFiles(
                                                  type: FileType.image,
                                                  withData: true,
                                                );
                                            if (result != null &&
                                                result.files.isNotEmpty) {
                                              final bytes =
                                                  result.files.first.bytes;
                                              if (bytes != null) {
                                                final ext =
                                                    result
                                                        .files
                                                        .first
                                                        .extension ??
                                                    'png';
                                                final b64 = base64Encode(bytes);
                                                final dataUri =
                                                    'data:image/$ext;base64,$b64';
                                                setState(() {
                                                  if (seg
                                                      .imageDataList
                                                      .isEmpty) {
                                                    seg.imageDataList.add(
                                                      dataUri,
                                                    );
                                                    seg.activeImageIndex = 0;
                                                  } else {
                                                    seg.imageDataList[seg
                                                            .activeImageIndex] =
                                                        dataUri;
                                                  }
                                                });
                                                c.forceUpdate();
                                                c.pushHistory();
                                              }
                                            }
                                          } catch (err) {
                                            debugPrint(
                                              "Error replacing image: $err",
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  // Stroke Color
                                  Tooltip(
                                    message: 'Stroke Color',
                                    child: ColorCircle(
                                      color: seg != null
                                          ? (parseHexColor(seg.color) ??
                                                const Color(0xFF22C55E))
                                          : const Color(0xFF22C55E),
                                      disabled: seg == null,
                                      onTap: () async {
                                        if (seg == null) return;
                                        final Color? picked =
                                            await showColorPickerSheet(
                                              btnCtx,
                                              parseHexColor(seg.color) ??
                                                  Colors.black,
                                            );
                                        if (picked != null) {
                                          setState(() {
                                            seg.color = colorToHex(picked);
                                          });
                                          c.forceUpdate();
                                          c.pushHistory();
                                        }
                                      },
                                    ),
                                  ),
                                  // Fill Color (Circle Only)
                                  if (seg != null && seg.type == 'circle') ...[
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: 'Fill Color',
                                      child: ColorCircle(
                                        color:
                                            parseHexColor(seg.fillColor) ??
                                            Colors.white,
                                        onTap: () async {
                                          final Color? picked =
                                              await showColorPickerSheet(
                                                btnCtx,
                                                parseHexColor(seg.fillColor) ??
                                                    Colors.white,
                                              );
                                          if (picked != null) {
                                            setState(() {
                                              seg.fillColor = colorToHex(
                                                picked,
                                              );
                                              seg.filled = true;
                                            });
                                            c.forceUpdate();
                                            c.pushHistory();
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                  // Cycle Fill Colors
                                  for (final entry in segCycles) ...[
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: 'Cycle (${entry.key})',
                                      child: ColorCircle(
                                        color:
                                            parseHexColor(
                                              entry.value.fillColor,
                                            ) ??
                                            const Color(0xFF9CA3AF),
                                        onTap: () async {
                                          final Color? picked =
                                              await showColorPickerSheet(
                                                btnCtx,
                                                parseHexColor(
                                                      entry.value.fillColor,
                                                    ) ??
                                                    Colors.grey,
                                              );
                                          if (picked != null) {
                                            setState(() {
                                              entry.value.fillColor =
                                                  colorToHex(picked);
                                              entry.value.filled = true;
                                            });
                                            c.forceUpdate();
                                            c.pushHistory();
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            } else {
                              // ── Tab 4: Segment Tools ──
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Point lock mode
                                  if (c.selectedPointIndex != null &&
                                      c.selectedPointIndex! <
                                          c.figure.points.length) ...[
                                    EditorIconButton(
                                      icon:
                                          c.pointModes[c.selectedPointIndex] ==
                                              'static'
                                          ? LucideIcons.lock
                                          : LucideIcons.lock_open,
                                      color: kToolColor,
                                      active:
                                          c.pointModes[c.selectedPointIndex] ==
                                          'static',
                                      onTap: () => c.togglePointMode(
                                        c.selectedPointIndex!,
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 32, height: 32),
                                  ],
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Flip',
                                    child: EditorIconButton(
                                      icon: LucideIcons.arrow_left_right,
                                      disabled: !canFlip,
                                      onTap: _handleFlip,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  EditorIconButton(
                                    icon: LucideIcons.chevron_up,
                                    disabled: !canFlip,
                                    onTap: _layerUp,
                                  ),
                                  const SizedBox(height: 4),
                                  EditorIconButton(
                                    icon: LucideIcons.chevron_down,
                                    disabled: !canFlip,
                                    onTap: _layerDown,
                                  ),
                                  if (seg != null && seg.type == 'text') ...[
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: 'Edit Text',
                                      child: EditorIconButton(
                                        icon: LucideIcons.file_pen,
                                        color: kToolColor,
                                        onTap: () => _editTextSegment(c, seg),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
          ),

          // Right sidebar.
          Positioned(
            top: 50 + pad.top,
            right: 4 + pad.right,
            child: OverlayCapsule(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isAnimateMode)
                    EditorIconButton(
                      icon: LucideIcons.layout_grid,
                      color: kToolColor,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FramesScreen(controller: c),
                        ),
                      ),
                    ),
                  if (c.isAnimateMode)
                    EditorIconButton(
                      icon: LucideIcons.settings,
                      color: kToolColor,
                      active: _rightTab == _RightTab.settings,
                      onTap: () => _openRightTab(_RightTab.settings),
                    ),
                  EditorIconButton(
                    icon: LucideIcons.sliders_horizontal,
                    color: kToolColor,
                    active: _rightTab == _RightTab.inspector,
                    onTap: () => _openRightTab(_RightTab.inspector),
                  ),
                  EditorIconButton(
                    icon: LucideIcons.layers,
                    color: kToolColor,
                    active: _rightTab == _RightTab.layers,
                    onTap: () => _openRightTab(_RightTab.layers),
                  ),
                  EditorIconButton(
                    icon: LucideIcons.delete,
                    color: kToolColor,
                    onTap: _handleReset,
                  ),
                ],
              ),
            ),
          ),

          // Zoom menu dropdown.
          if (_showMenu)
            Positioned(
              top: 50 + pad.top,
              right: 4 + pad.right,
              child: ConstrainedBox(
                // Cap the height so long menus scroll instead of overflowing
                // the screen.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height - pad.top - 50,
                ),
                child: EditorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MenuItem(
                          icon: LucideIcons.upload,
                          label: 'Import SVG',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.importSvg().then((msg) {
                              if (msg != null) _showSnack(msg);
                            });
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.image,
                          label: 'Import SVG as Image',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.importSvgAsImage().then((msg) {
                              if (msg != null) _showSnack(msg);
                            });
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.user,
                          label: 'Import Minecraft Skin',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.importMinecraftSkin(context).then(
                              (msg) {
                                if (msg != null) _showSnack(msg);
                              },
                            );
                          },
                        ),
                        _MenuItem(
                          icon: c.showConnectors ? LucideIcons.link : LucideIcons.link_2_off,
                          label: c.showConnectors
                              ? 'Hide Connectors'
                              : 'Show Connectors',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.toggleConnectors();
                          },
                        ),
                        _MenuItem(
                          icon: c.showAxis ? LucideIcons.grid_3x3 : LucideIcons.grid_3x3,
                          label: c.showAxis
                              ? 'Hide Grid Axis'
                              : 'Show Grid Axis',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.toggleAxis();
                          },
                        ),
                        _MenuItem(
                          icon: c.snapEnabled ? LucideIcons.grid_3x3 : LucideIcons.grid_3x3,
                          label: c.snapEnabled ? 'Snap: On' : 'Snap: Off',
                          onTap: () {
                            setState(() => _showMenu = false);
                            widget.controller.toggleSnap();
                            _showSnack(c.snapEnabled ? 'Snap on' : 'Snap off');
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.circle_play,
                          label: 'Preview',
                          onTap: () {
                            setState(() => _showMenu = false);
                            _openPreview();
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.file_image,
                          label: 'Export GIF',
                          onTap: () {
                            setState(() => _showMenu = false);
                            _exportGif();
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.images,
                          label: 'Export PNG Frames',
                          onTap: () {
                            setState(() => _showMenu = false);
                            _exportPngZip();
                          },
                        ),
                        // Animation projects are finished movies (GIF/PNG output);
                        // Presets/Figures are reusable assets and keep Lottie.
                        if (!c.isAnimationProject)
                          _MenuItem(
                            icon: LucideIcons.film,
                            label: 'Export Lottie',
                            onTap: () {
                              setState(() => _showMenu = false);
                              _exportLottie();
                            },
                          ),
                        _MenuItem(
                          icon: LucideIcons.bookmark,
                          label: 'Poses',
                          onTap: () {
                            setState(() => _showMenu = false);
                            _openPoseLibrary();
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.plus,
                          label: 'Zoom In',
                          onTap: () {
                            c.zoomIn();
                            setState(() => _showMenu = false);
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.minus,
                          label: 'Zoom Out',
                          onTap: () {
                            c.zoomOut();
                            setState(() => _showMenu = false);
                          },
                        ),
                        _MenuItem(
                          icon: LucideIcons.maximize,
                          label: 'Reset Zoom',
                          onTap: () {
                            c.zoomReset();
                            setState(() => _showMenu = false);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editTextSegment(EditorController c, Segment seg) async {
    final textController = TextEditingController(text: seg.text ?? '');
    final sizeController = TextEditingController(
      text: seg.textSize.toStringAsFixed(0),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17191E),
        title: const Text('Edit Text', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Type something…',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.lightBlueAccent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sizeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Size',
                  labelStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.lightBlueAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('ok'),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == 'ok') {
      final text = textController.text.trim();
      setState(() {
        seg.text = text.isEmpty ? 'Text' : text;
        final size = double.tryParse(sizeController.text);
        seg.textSize = (size == null || size <= 0) ? 32 : size;
      });
      c.forceUpdate();
      c.pushHistory();
    }
    textController.dispose();
    sizeController.dispose();
  }

  void _openPreview() {
    final c = widget.controller;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FigurePreviewScreen(
          figure: c.figure,
          animation: c.currentAnimation,
          fps: c.figure.fps <= 0 ? 12 : c.figure.fps,
          initialTime: c.currentTime,
        ),
      ),
    );
  }

  void _exportGif() {
    final c = widget.controller;
    _exportOptions(
      title: 'Export GIF',
      fields: const [_ExportOption.fps(), _ExportOption.scale()],
      loop: true,
    ).then((opts) {
      if (opts == null) return;
      _runExport(
        label: 'Rendering GIF…',
        job: () => FigureExport(
          c.figure,
          animation: c.currentAnimation,
        ).renderGif(fps: opts.fps, scale: opts.scale, loop: opts.loop),
        fileName: 'animation.gif',
        extensions: const ['gif'],
      );
    });
  }

  void _exportPngZip() {
    final c = widget.controller;
    _exportOptions(
      title: 'Export PNG Frames',
      fields: const [_ExportOption.scale()],
    ).then((opts) {
      if (opts == null) return;
      _runExport(
        label: 'Rendering PNG frames…',
        job: () => FigureExport(
          c.figure,
          animation: c.currentAnimation,
        ).renderPngZip(scale: opts.scale),
        fileName: 'frames.zip',
        extensions: const ['zip'],
      );
    });
  }

  void _exportLottie() {
    final c = widget.controller;
    _showSnack('Building Lottie…');
    exportLottieJson(c.figure, c.currentAnimation)
        .then((json) {
          final bytes = utf8.encode(json);
          FilePicker.saveFile(
            bytes: bytes,
            fileName: 'animation.json',
            type: FileType.custom,
            allowedExtensions: ['json'],
            dialogTitle: 'Export Lottie',
          ).then((path) {
            if (path != null) _showSnack('Lottie saved');
          });
        })
        .catchError((_) {
          if (mounted) _showSnack('Lottie export failed');
        });
  }

  Future<_ExportOptions?> _exportOptions({
    required String title,
    required List<_ExportOption> fields,
    bool loop = false,
  }) async {
    var fps = 12.0;
    var scale = 2.0;
    var loopVal = loop;
    final controllers = {
      'fps': TextEditingController(text: '12'),
      'scale': TextEditingController(text: '2'),
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17191E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StatefulBuilder(
                    builder: (ctx, setStateLocal) => TextField(
                      controller: controllers[field.key],
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: field.label,
                        labelStyle: const TextStyle(color: Colors.white38),
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.lightBlueAccent),
                        ),
                      ),
                    ),
                  ),
                ),
              if (loop)
                StatefulBuilder(
                  builder: (ctx, setStateLocal) => Row(
                    children: [
                      const Text('Loop', style: TextStyle(color: Colors.white)),
                      const Spacer(),
                      Switch(
                        value: loopVal,
                        onChanged: (v) => setState(() => loopVal = v),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    final fpsText = controllers['fps']?.text;
    final scaleText = controllers['scale']?.text;
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result != true) return null;
    fps = double.tryParse(fpsText ?? '') ?? 12;
    if (fps <= 0 || fps > 60) fps = 12;
    scale = double.tryParse(scaleText ?? '') ?? 2;
    if (scale <= 0 || scale > 8) scale = 2;
    return _ExportOptions(fps: fps, scale: scale, loop: loopVal);
  }

  void _runExport({
    required String label,
    required Future<Uint8List> Function() job,
    required String fileName,
    required List<String> extensions,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            job()
                .then((bytes) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  FilePicker.saveFile(
                    bytes: bytes,
                    fileName: fileName,
                    type: FileType.custom,
                    allowedExtensions: extensions,
                    dialogTitle: 'Export',
                  ).then((path) {
                    if (path != null) {
                      // ignore: use_build_context_synchronously
                      if (mounted) _showSnack('$fileName saved');
                    }
                  });
                })
                .catchError((_) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) _showSnack('Export failed');
                });
            return AlertDialog(
              backgroundColor: const Color(0xFF17191E),
              content: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Text(label, style: const TextStyle(color: Colors.white)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openPoseLibrary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return PoseLibrarySheet(controller: widget.controller);
      },
    );
  }

  Future<void> _showOpacitySlider(EditorController c, int ptIdx) async {
    final comp = c.figure.connectedComponent(ptIdx);
    final root = c.figure.rootIndices.firstWhere(
      (r) => comp.contains(r),
      orElse: () => -1,
    );
    if (root == -1) return;

    double currentVal = c.figure.getFigureOpacity(root, c.currentTime);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final palette = Theme.of(context).appColors;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.backgroundElement,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.backgroundSelected),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Opacity',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: currentVal,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  activeColor: const Color(0xFF10B981),
                  inactiveColor: palette.backgroundSelected,
                  onChanged: (val) {
                    setModalState(() => currentVal = val);
                    c.setFigureOpacity(ptIdx, val);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
