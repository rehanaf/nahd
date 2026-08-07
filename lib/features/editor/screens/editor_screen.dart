import 'package:flutter/material.dart';

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
  String _lastSegmentKey = 'line';
  String _lastRigKey = 'rig';

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

  /// Segment (sidebar) group: new segment / line / circle / join mapping.
  bool _isSegmentTool(EditorTool t) =>
      t == EditorTool.line ||
      t == EditorTool.circle ||
      t == EditorTool.join;

  String _segmentKey(EditorTool t) {
    if (_isSegmentTool(t)) {
      if (_lastSegmentKey != 'newSegment' || t != _segmentTool(_lastSegmentKey)) {
        _lastSegmentKey = switch (t) {
          EditorTool.circle => 'circle',
          EditorTool.join => 'join',
          _ => 'line',
        };
      }
    }
    print("Mapper _segmentKey activeTool: $t, returning $_lastSegmentKey");
    return _lastSegmentKey;
  }

  EditorTool _segmentTool(String key) => switch (key) {
        'circle' => EditorTool.circle,
        'join' => EditorTool.join,
        _ => EditorTool.line,
      };

  /// Scene mode group (rig / asset / anchor) mapping.
  String _rigKey(RigMode m) {
    _lastRigKey = switch (m) {
      RigMode.asset => 'asset',
      RigMode.anchor => 'anchor',
      _ => 'rig',
    };
    return _lastRigKey;
  }

  RigMode _rigMode(String key) => switch (key) {
        'asset' => RigMode.asset,
        'anchor' => RigMode.anchor,
        _ => RigMode.rig,
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

  Future<void> _openAddFigure() async {
    final list = await ProjectStorage.listProjects(ProjectType.figure);
    if (!mounted) return;
    final meta = await showModalBottomSheet<ProjectMeta>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _AddFigureSheet(projects: list),
    );
    if (meta != null) _handleAddFigure(meta);
  }

  Future<void> _openNewSegment() async {
    final c = widget.controller;
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _NewSegmentSheet(),
    );
    if (type == null || !mounted) return;
    c.addSegment(type);
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tab.name.toUpperCase(),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
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
      endDrawer: _buildDrawer(c, palette),
      onEndDrawerChanged: (opened) {
        if (!opened && _rightTab != null) {
          setState(() => _rightTab = null);
        }
      },
      body: Stack(
        children: [
          Positioned.fill(child: FigureCanvas(controller: c)),

          // Top-left: back + undo/redo.
          Positioned(
            top: 8 + pad.top,
            left: 8 + pad.left,
            child: Row(
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
              ],
            ),
          ),

          // Top-right: tool capsule + more (zoom) menu button.
          Positioned(
            top: 8 + pad.top,
            right: 8 + pad.right,
            child: Row(
              children: [
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
                      // Scene mode group (independent from the active tool):
                      // one of rig / asset / anchor is always active.
                      ToolGroupButton(
                        subTools: const [
                          ToolGroupSub(
                              icon: Icons.accessibility_new,
                              key: 'rig',
                              color: Color(0xFF22C55E)),
                          ToolGroupSub(
                              icon: Icons.crop_rotate,
                              key: 'asset',
                              color: Color(0xFF8B5CF6)),
                          ToolGroupSub(
                              icon: Icons.anchor,
                              key: 'anchor',
                              color: Color(0xFF10B981)),
                        ],
                        selectedKey: _rigKey(c.rigMode),
                        onSelect: (k) => c.setRigMode(_rigMode(k)),
                        active: true,
                        onActivate: () {},
                        placement: ToolGroupPlacement.bottom,
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
          ),

          // Left sidebar.
          Positioned(
            top: 52 + pad.top,
            left: 4 + pad.left,
            child: OverlayCapsule(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isAnimateMode) ...[
                    EditorIconButton(
                      icon: Icons.create_new_folder,
                      color: const Color(0xFF22C55E),
                      onTap: _openAddFigure,
                    ),
                    const Divider(height: 8),
                  ],
                  ToolGroupButton(
                    subTools: const [
                      ToolGroupSub(
                          icon: Icons.control_point,
                          key: 'newSegment',
                          color: Color(0xFF8B5CF6)),
                      ToolGroupSub(
                          icon: Icons.edit,
                          key: 'line',
                          color: Color(0xFF22C55E)),
                      ToolGroupSub(
                          icon: Icons.panorama_fish_eye,
                          key: 'circle',
                          color: Color(0xFF22C55E)),
                      ToolGroupSub(
                          icon: Icons.join_inner,
                          key: 'join',
                          color: Color(0xFFF97316)),
                    ],
                    selectedKey: _segmentKey(c.activeTool),
                    onSelect: (k) {
                      setState(() => _lastSegmentKey = k);
                      if (k == 'newSegment') {
                        _openNewSegment();
                      } else {
                        c.setTool(_segmentTool(k));
                      }
                    },
                    active: c.activeTool == EditorTool.line ||
                        c.activeTool == EditorTool.circle ||
                        c.activeTool == EditorTool.join ||
                        _lastSegmentKey == 'newSegment',
                    onActivate: () {
                      if (_lastSegmentKey == 'newSegment') {
                        _openNewSegment();
                      } else {
                        c.setTool(_segmentTool(_lastSegmentKey));
                      }
                    },
                    placement: ToolGroupPlacement.right,
                  ),
                  const Divider(height: 8),
                  Tooltip(
                    message: 'Flip',
                    child: EditorIconButton(
                      icon: Icons.swap_horiz,
                      disabled: !canFlip,
                      onTap: _handleFlip,
                    ),
                  ),
                  _LineCapButton(
                    selectedSeg: canFlip
                        ? c.figure.getSegment(c.selectedSegmentId!)
                        : null,
                    onTap: _cycleLineCap,
                  ),
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
                  ],
                  const Divider(height: 8),
                  EditorIconButton(
                    icon: Icons.keyboard_arrow_up,
                    disabled: !canFlip,
                    onTap: _layerUp,
                  ),
                  EditorIconButton(
                    icon: Icons.keyboard_arrow_down,
                    disabled: !canFlip,
                    onTap: _layerDown,
                  ),
                ],
              ),
            ),
          ),

          // Right sidebar.
          Positioned(
            top: (c.isAnimateMode ? 96 : 52) + pad.top,
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

          // Transport bar.
          if (c.isAnimateMode)
            Positioned(
              top: 52 + pad.top,
              right: 8 + pad.right,
              child: AnimationTransport(controller: c),
            ),

          // Zoom menu dropdown.
          if (_showMenu)
            Positioned(
              top: 56 + pad.top,
              right: 8 + pad.right,
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

