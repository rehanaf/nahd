import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/color_picker_sheet.dart';

import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';
import '../../../core/project_storage.dart';
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

  void _cycleLineCap() {
    final c = widget.controller;
    final segId = c.selectedSegmentId;
    if (segId == null) return;
    final seg = c.figure.getSegment(segId);
    if (seg == null) return;
    const caps = ['round', 'square', 'butt'];
    final idx = caps.indexOf(seg.lineCap);
    seg.lineCap = caps[(idx + 1) % caps.length];
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
      final xs = srcPts.map((p) => p.x).toList();
      final ys = srcPts.map((p) => p.y).toList();
      final minX = xs.reduce((a, b) => a < b ? a : b);
      final minY = ys.reduce((a, b) => a < b ? a : b);
      final maxY = ys.reduce((a, b) => a > b ? a : b);
      final curMaxX = c.figure.points.isEmpty
          ? -100
          : c.figure.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
      final offsetX = curMaxX + 100 - minX;
      final offsetY = -((minY + maxY) / 2);

      final indexMap = <int, int>{};
      final base = c.figure.points.length;
      for (var i = 0; i < srcPts.length; i++) {
        indexMap[i] = base + i;
        c.figure.points.add(Point2(srcPts[i].x + offsetX, srcPts[i].y + offsetY));
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
        for (final r in newRoots) {
          if (c.currentTime > 0.001) {
            c.figure.setFigureVisibility(r, 0, false);
          }
          c.figure.setFigureVisibility(r, c.currentTime, true);
        }
      }
      for (final s in src.segments) {
        final p1 = indexMap[s.point1Index];
        final p2 = indexMap[s.point2Index];
        if (p1 == null || p2 == null) continue;
        final ns = s.clone();
        ns.point1Index = p1;
        ns.point2Index = p2;
        ns.layer = (ns.layer) + c.figure.segments.length;
        c.figure.segments.add(ns);
      }
      src.cycleFills.forEach((key, entry) {
        final parts = key.split(',').map(int.tryParse).whereType<int>().toList();
        if (parts.length != 2) return;
        final a = indexMap[parts[0]];
        final b = indexMap[parts[1]];
        if (a == null || b == null) return;
        c.figure.cycleFills['$a,$b'] = entry.clone();
      });
      c.mergeGroupsFrom(src);
      c.forceUpdate();
      c.pushHistory();
    } catch (_) {
      // ignore
    }
  }

  void _showSnack(String message) {
    final palette = Theme.of(context).appColors;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: palette.text)),
      backgroundColor: palette.backgroundElement,
      behavior: SnackBarBehavior.floating,
    ));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memilih gambar')),
        );
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
                  icon: const Icon(Icons.close, size: 18),
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
                  icon: Icons.edit,
                  label: 'Line',
                  color: const Color(0xFF22C55E),
                  onTap: () {
                    c.addSegment('line');
                    Navigator.of(context).pop();
                  },
                  palette: palette,
                ),
                _drawerSegmentIcon(
                  icon: Icons.panorama_fish_eye,
                  label: 'Circle',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    c.addSegment('circle');
                    Navigator.of(context).pop();
                  },
                  palette: palette,
                ),
                _drawerSegmentIcon(
                  icon: Icons.image,
                  label: 'Image',
                  color: const Color(0xFFEC4899),
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
              "ADD FIGURE ASSET",
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
              ]),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data ?? [[], []];
                final groups = List<ProjectGroup>.from(data[0] as List);
                final projects = List<ProjectMeta>.from(data[1] as List);
                final filtered = projects.where((p) => p.id != c.projectId).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "No other figures found",
                        style: TextStyle(color: palette.textSecondary, fontSize: 12),
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
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          group.name,
                          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        leading: Icon(Icons.folder, color: palette.textSecondary, size: 18),
                        childrenPadding: const EdgeInsets.only(left: 16),
                        initiallyExpanded: true,
                        children: groupProjects.map((p) => _buildFigureListTile(p, palette)).toList(),
                      ),
                    ),
                  );
                }

                final activeGroupIds = groups.map((g) => g.id).toSet();
                final ungroupedProjects = filtered.where((p) => p.groupId == null || !activeGroupIds.contains(p.groupId)).toList();
                if (ungroupedProjects.isNotEmpty) {
                  displayGroups.add(
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          "Default / Ungrouped",
                          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        leading: Icon(Icons.folder_open, color: palette.textSecondary, size: 18),
                        childrenPadding: const EdgeInsets.only(left: 16),
                        initiallyExpanded: true,
                        children: ungroupedProjects.map((p) => _buildFigureListTile(p, palette)).toList(),
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
          "ID: ${meta.id.substring(0, math.min(8, meta.id.length))}...",
          style: TextStyle(color: palette.textSecondary, fontSize: 11),
        ),
        trailing: Icon(Icons.add, color: palette.text, size: 16),
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
                  icon: const Icon(Icons.close, size: 18),
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
        final canFlip = c.selectedSegmentId != null &&
            c.figure.getSegment(c.selectedSegmentId!) != null;
        return _buildScaffold(context, c, palette, canFlip);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, EditorController c,
      AppPalette palette, bool canFlip) {
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
            top: 4,
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
                          child: Icon(Icons.arrow_back, size: 18, color: palette.text),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OverlayCapsule(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          EditorIconButton(
                            icon: Icons.undo,
                            disabled: !c.canUndo,
                            onTap: c.undo,
                          ),
                          EditorIconButton(
                            icon: Icons.redo,
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
                            icon: Icons.create_new_folder,
                            color: const Color(0xFF22C55E),
                            onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          ),
                          const SizedBox(width: 4),
                          EditorIconButton(
                            icon: Icons.join_inner,
                            color: const Color(0xFFF97316),
                            active: c.activeTool == EditorTool.join,
                            onTap: () => c.setTool(EditorTool.join),
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
                        icon: Icons.rotate_right,
                        color: const Color(0xFFF97316),
                        active: c.activeTool == EditorTool.rotate,
                        onTap: () => c.setTool(EditorTool.rotate),
                      ),
                      // Modify group (Point, Modify, Curve).
                      ToolGroupButton(
                        subTools: const [
                          ToolGroupSub(
                              icon: Icons.open_with,
                              key: 'point',
                              color: Color(0xFF3B82F6)),
                          ToolGroupSub(
                              icon: Icons.center_focus_strong,
                              key: 'modify',
                              color: Color(0xFF06B6D4)),
                          ToolGroupSub(
                              icon: Icons.timeline,
                              key: 'curve',
                              color: Color(0xFFEC4899)),
                        ],
                        selectedKey: _modifyKey(c.activeTool),
                        onSelect: (k) {
                          setState(() => _lastModifyKey = k);
                          c.setTool(_modifyTool(k));
                        },
                        active: _isModifyTool(c.activeTool),
                        onActivate: () => c.setTool(_modifyTool(_lastModifyKey)),
                        placement: ToolGroupPlacement.bottom,
                      ),
                      // Transform group (Move All, Rotate All, Scale All).
                      ToolGroupButton(
                        subTools: const [
                          ToolGroupSub(
                              icon: Icons.near_me,
                              key: 'moveAll',
                              color: Color(0xFF22C55E)),
                          ToolGroupSub(
                              icon: Icons.rotate_left,
                              key: 'rotateAll',
                              color: Color(0xFFEAB308)),
                          ToolGroupSub(
                              icon: Icons.compress,
                              key: 'scaleAll',
                              color: Color(0xFFF97316)),
                        ],
                        selectedKey: _transformKey(c.activeTool),
                        onSelect: (k) {
                          setState(() => _lastTransformKey = k);
                          c.setTool(_transformTool(k));
                        },
                        active: _isTransformTool(c.activeTool),
                        onActivate: () => c.setTool(_transformTool(_lastTransformKey)),
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
                              icon: Icons.accessibility_new,
                              color: const Color(0xFF22C55E),
                              active: c.rigMode == RigMode.rig,
                              onTap: () => c.setRigMode(RigMode.rig),
                            ),
                            EditorIconButton(
                              icon: Icons.crop_rotate,
                              color: const Color(0xFF8B5CF6),
                              active: c.rigMode == RigMode.asset,
                              onTap: () => c.setRigMode(RigMode.asset),
                            ),
                            EditorIconButton(
                              icon: Icons.anchor,
                              color: const Color(0xFF10B981),
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
                          child: Icon(Icons.more_horiz, size: 18, color: palette.text),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Left sidebar.
          Positioned(
            top: 48,
            left: 4 + pad.left,
            child: OverlayCapsule(
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Left column
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (btnCtx) {
                          final activeTool = c.activeTool;
                          final seg = c.selectedSegmentId != null
                              ? c.figure.getSegment(c.selectedSegmentId!)
                              : null;
                          IconData toolIcon = Icons.edit;
                          Color toolIconColor = const Color(0xFF22C55E);

                          if (activeTool == EditorTool.circle) {
                            toolIcon = Icons.panorama_fish_eye;
                          } else if (activeTool == EditorTool.image) {
                            toolIcon = Icons.image;
                          } else if (activeTool == EditorTool.none) {
                            toolIcon = Icons.visibility_off;
                            toolIconColor = Colors.grey;
                          }

                          final isDrawingTool = activeTool == EditorTool.line ||
                              activeTool == EditorTool.circle ||
                              activeTool == EditorTool.image ||
                              activeTool == EditorTool.none;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Tombol 1: Switch Drawing Tool
                              Tooltip(
                                message: 'Switch Tool: ${activeTool.name.toUpperCase()}',
                                child: EditorIconButton(
                                  icon: toolIcon,
                                  color: toolIconColor,
                                  active: isDrawingTool,
                                  onTap: () {
                                    EditorTool nextTool = EditorTool.line;
                                    if (activeTool == EditorTool.line) {
                                      nextTool = EditorTool.circle;
                                    } else if (activeTool == EditorTool.circle) {
                                      nextTool = EditorTool.image;
                                    } else if (activeTool == EditorTool.image) {
                                      nextTool = EditorTool.none;
                                    } else {
                                      nextTool = EditorTool.line;
                                    }
                                    c.setTool(nextTool);
                                    setState(() {});
                                  },
                                ),
                              ),
                              // Tombol 2: Switch Selected Segment Type (hanya jika ada segment terpilih)
                              if (seg != null) ...[
                                const SizedBox(height: 4),
                                Tooltip(
                                  message: 'Switch Selected Type (${seg.type})',
                                  child: EditorIconButton(
                                    icon: Icons.loop,
                                    color: const Color(0xFF3B82F6),
                                    onTap: () {
                                      final oldType = seg.type;
                                      String nextType = 'line';
                                      if (oldType == 'line') {
                                        nextType = 'circle';
                                      } else if (oldType == 'circle') {
                                        nextType = 'image';
                                      } else if (oldType == 'image') {
                                        nextType = 'none';
                                      } else {
                                        nextType = 'line';
                                      }
                                      setState(() {
                                        seg.type = nextType;
                                        seg.filled = nextType != 'circle' && nextType != 'none';
                                      });
                                      c.forceUpdate();
                                      c.pushHistory();
                                    },
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Tombol 3: Dynamic Circle Color Picker untuk segment terpilih (Stroke Color)
                                Tooltip(
                                  message: 'Segment Stroke Color',
                                  child: EditorIconButton(
                                    icon: Icons.circle,
                                    color: parseHexColor(seg.color) ?? const Color(0xFF22C55E),
                                    onTap: () async {
                                      final Color? picked = await showColorPickerSheet(
                                        btnCtx,
                                        parseHexColor(seg.color) ?? Colors.black,
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
                                // Tombol 4: Dynamic Circle Color Picker untuk segment terpilih (Fill Color - Circle Only)
                                if (seg.type == 'circle') ...[
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Segment Fill Color',
                                    child: EditorIconButton(
                                      icon: Icons.circle_outlined,
                                      color: parseHexColor(seg.fillColor) ?? Colors.white,
                                      onTap: () async {
                                        final Color? picked = await showColorPickerSheet(
                                          btnCtx,
                                          parseHexColor(seg.fillColor) ?? Colors.white,
                                        );
                                        if (picked != null) {
                                          setState(() {
                                            seg.fillColor = colorToHex(picked);
                                            seg.filled = true;
                                          });
                                          c.forceUpdate();
                                          c.pushHistory();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                                // Tombol 5: Upload/Replace Image untuk segment terpilih (Image Only)
                                if (seg.type == 'image') ...[
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: 'Replace Image Source',
                                    child: EditorIconButton(
                                      icon: Icons.image_search,
                                      color: const Color(0xFF10B981),
                                      onTap: () async {
                                        try {
                                          final result = await FilePicker.pickFiles(
                                            type: FileType.image,
                                            withData: true,
                                          );
                                          if (result != null && result.files.isNotEmpty) {
                                            final bytes = result.files.first.bytes;
                                            if (bytes != null) {
                                              final ext = result.files.first.extension ?? 'png';
                                              final b64 = base64Encode(bytes);
                                              final dataUri = 'data:image/$ext;base64,$b64';
                                              setState(() {
                                                seg.imageData = dataUri;
                                              });
                                              c.forceUpdate();
                                              c.pushHistory();
                                            }
                                          }
                                        } catch (err) {
                                          debugPrint("Error replacing image: $err");
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Tooltip(
                        message: 'Flip',
                        child: EditorIconButton(
                          icon: Icons.swap_horiz,
                          disabled: !canFlip,
                          onTap: _handleFlip,
                        ),
                      ),
                      const SizedBox(height: 4),
                      EditorIconButton(
                        icon: Icons.keyboard_arrow_up,
                        disabled: !canFlip,
                        onTap: _layerUp,
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  // Right column
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Placeholder/Point lock mode
                      if (c.selectedPointIndex != null &&
                          c.selectedPointIndex! < c.figure.points.length) ...[
                        EditorIconButton(
                          icon: c.pointModes[c.selectedPointIndex] == 'static'
                              ? Icons.lock
                              : Icons.lock_open,
                          color: const Color(0xFF2563EB),
                          active: c.pointModes[c.selectedPointIndex] == 'static',
                          onTap: () => c.togglePointMode(c.selectedPointIndex!),
                        ),
                      ] else ...[
                        // Maintain vertical alignment if point mode is hidden
                        const SizedBox(width: 32, height: 32),
                      ],
                      const SizedBox(height: 4),
                      _LineCapButton(
                        selectedSeg: canFlip
                            ? c.figure.getSegment(c.selectedSegmentId!)
                            : null,
                        onTap: _cycleLineCap,
                      ),
                      const SizedBox(height: 4),
                      // Maintain vertical alignment for segment / flip spacers
                      const SizedBox(width: 32, height: 32),
                      const SizedBox(height: 4),
                      EditorIconButton(
                        icon: Icons.keyboard_arrow_down,
                        disabled: !canFlip,
                        onTap: _layerDown,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Right sidebar.
          Positioned(
            top: 48,
            right: 4 + pad.right,
            child: OverlayCapsule(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isAnimateMode)
                    EditorIconButton(
                      icon: Icons.grid_view_outlined,
                      color: const Color(0xFF22C55E),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FramesScreen(controller: c),
                        ),
                      ),
                    ),
                  if (c.isAnimateMode)
                    EditorIconButton(
                      icon: Icons.settings,
                      color: const Color(0xFF0EA5E9),
                      active: _rightTab == _RightTab.settings,
                      onTap: () => _openRightTab(_RightTab.settings),
                    ),
                  EditorIconButton(
                    icon: Icons.tune,
                    color: const Color(0xFF9333EA),
                    active: _rightTab == _RightTab.inspector,
                    onTap: () => _openRightTab(_RightTab.inspector),
                  ),
                  EditorIconButton(
                    icon: Icons.layers,
                    color: const Color(0xFF0D9488),
                    active: _rightTab == _RightTab.layers,
                    onTap: () => _openRightTab(_RightTab.layers),
                  ),
                  EditorIconButton(
                    icon: Icons.delete,
                    color: const Color(0xFFEF4444),
                    onTap: _handleReset,
                  ),
                ],
              ),
            ),
          ),

          // Zoom menu dropdown.
          if (_showMenu)
            Positioned(
              top: 48,
              right: 4 + pad.right,
              child: EditorPanel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MenuItem(
                      icon: Icons.upload_file,
                      label: 'Import SVG',
                      onTap: () {
                        setState(() => _showMenu = false);
                        widget.controller.importSvg().then((msg) {
                          if (msg != null) _showSnack(msg);
                        });
                      },
                    ),
                    _MenuItem(
                      icon: Icons.image,
                      label: 'Import SVG as Image',
                      onTap: () {
                        setState(() => _showMenu = false);
                        widget.controller.importSvgAsImage().then((msg) {
                          if (msg != null) _showSnack(msg);
                        });
                      },
                    ),
                    _MenuItem(
                      icon: c.showConnectors
                          ? Icons.link
                          : Icons.link_off,
                      label: c.showConnectors
                          ? 'Hide Connectors'
                          : 'Show Connectors',
                      onTap: () {
                        c.toggleConnectors();
                        setState(() => _showMenu = false);
                      },
                    ),
                    _MenuItem(
                      icon: Icons.add,
                      label: 'Zoom In',
                      onTap: () {
                        c.zoomIn();
                        setState(() => _showMenu = false);
                      },
                    ),
                    _MenuItem(
                      icon: Icons.remove,
                      label: 'Zoom Out',
                      onTap: () {
                        c.zoomOut();
                        setState(() => _showMenu = false);
                      },
                    ),
                    _MenuItem(
                      icon: Icons.fullscreen,
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

        ],
      ),
    );
  }
}

