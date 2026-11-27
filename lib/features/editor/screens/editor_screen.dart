import 'dart:convert';
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
import '../../../core/scene/predefined_projects.dart';
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
  final void Function(String id, ProjectType type)? onOpenProject;

  const EditorScreen({
    super.key,
    required this.controller,
    required this.onBack,
    this.onOpenProject,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _RightTab { settings, inspector, layers, addSegment }

class _EditorScreenState extends State<EditorScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _RightTab? _rightTab;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Menu & Projects",
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
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
            child: FutureBuilder<List<ProjectMeta>>(
              future: ProjectStorage.listProjects(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final projects = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  children: [
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(LucideIcons.plus, size: 18, color: kToolColor),
                      title: Text(
                        'Buat Projek Baru',
                        style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        final name = await _showCreateProjectPrompt(context, palette, c.projectType ?? ProjectType.animation);
                        if (name != null && name.trim().isNotEmpty && widget.onOpenProject != null) {
                          final meta = await ProjectStorage.createProject(c.projectType ?? ProjectType.animation, name);
                          widget.onOpenProject!(meta.id, meta.type);
                        }
                      },
                    ),
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(LucideIcons.arrow_left, size: 18, color: palette.textSecondary),
                      title: Text(
                        'Kembali (Menu Utama)',
                        style: TextStyle(color: palette.text, fontSize: 14),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onBack();
                      },
                    ),
                    const Divider(height: 24, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        "PILIH PROJEK",
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (projects.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'No projects found',
                            style: TextStyle(color: palette.textSecondary, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      ...projects.map((meta) {
                        final isCurrent = meta.id == c.projectId;
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: isCurrent ? palette.backgroundElement.withValues(alpha: 0.8) : null,
                          selected: isCurrent,
                          leading: Icon(
                            meta.type == ProjectType.animation
                                ? LucideIcons.film
                                : meta.type == ProjectType.preset
                                    ? LucideIcons.box
                                    : LucideIcons.user,
                            size: 18,
                            color: isCurrent ? kToolColor : palette.textSecondary,
                          ),
                          title: Text(
                            meta.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            meta.type.name.toUpperCase(),
                            style: TextStyle(color: palette.textSecondary, fontSize: 10),
                          ),
                          trailing: isCurrent
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: kToolColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Current',
                                    style: TextStyle(color: kToolColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : null,
                          onTap: widget.onOpenProject == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onOpenProject!(meta.id, meta.type);
                                },
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCreateProjectPrompt(BuildContext context, AppPalette palette, ProjectType type) async {
    final textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.backgroundElement,
        title: Text('Buat Projek Baru', style: TextStyle(color: palette.text)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            hintText: 'Nama projek...',
            hintStyle: TextStyle(color: palette.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('Batal', style: TextStyle(color: palette.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kToolColor),
            onPressed: () => Navigator.of(ctx).pop(textController.text),
            child: const Text('Buat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddMenuSheet(BuildContext context, EditorController c, AppPalette palette) {
    _openRightTab(_RightTab.addSegment);
  }

  Widget _buildAddSegmentContent(EditorController c, AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "ADD SEGMENT",
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
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
              onTap: () {
                Navigator.of(context).pop();
                _pickAndAddImageSegment(c);
              },
              palette: palette,
            ),
          ],
        ),
        const Divider(height: 24, thickness: 1),
        Text(
          "LIST FIGURE (TEMPLATES)",
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kToolColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.user, size: 16),
              label: const Text('Add Stickman'),
              onPressed: () {
                Navigator.of(context).pop();
                final fig = Figure.fromJsonString(PredefinedProjects.stickmanFigureJson);
                c.mergeImportedFigure(fig);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kToolColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.circle, size: 16),
              label: const Text('Add Bounce Ball'),
              onPressed: () {
                Navigator.of(context).pop();
                final fig = Figure.fromJsonString(PredefinedProjects.bounceFigureJson);
                c.mergeImportedFigure(fig);
              },
            ),
          ],
        ),
      ],
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
              borderRadius: BorderRadius.circular(10),
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
                        : tab == _RightTab.layers
                        ? "Layers"
                        : "Add Segment & Figure",
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
              _RightTab.addSegment => _buildAddSegmentContent(c, palette),
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
                        width: 40,
                        height: 40,
                        child: InkWell(
                          onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          borderRadius: BorderRadius.circular(10),
                          child: Icon(
                            LucideIcons.menu,
                            size: 20,
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
                      child: EditorIconButton(
                        icon: LucideIcons.folder_plus,
                        color: kToolColor,
                        onTap: () => _showAddMenuSheet(context, c, palette),
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
                        width: 40,
                        height: 40,
                        child: InkWell(
                          onTap: () => _openMoreMenu(c, palette),
                          borderRadius: BorderRadius.circular(10),
                          child: Icon(
                            LucideIcons.ellipsis,
                            size: 20,
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
            top: 56 + pad.top,
            left: 4 + pad.left,
            child: c.isAnimateMode
                ? OverlayCapsule(
                    padding: const EdgeInsets.all(4),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Delete / Visibility',
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
                                    if (c.isAnimateMode) {
                                      c.hideFigureAtCurrentFrame(ptIdx);
                                    } else {
                                      c.removeFigureAt(root);
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                            const SizedBox(height: 4),
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
                            const SizedBox(height: 4),
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
                            const SizedBox(height: 4),
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
                            const SizedBox(height: 4),
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
                            const SizedBox(height: 4),
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
                            const SizedBox(height: 4),
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
                                    const SizedBox(width: 40, height: 40),
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
            top: 56 + pad.top,
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

                ],
              ),
            ),
          ),

          // Horizontal prev/next sprite toolbar (appears when selected segment has sprites)
          if (c.selectedSegmentId != null &&
              c.figure.getSegment(c.selectedSegmentId!) != null &&
              c.figure.getSegment(c.selectedSegmentId!)!.imageDataList.isNotEmpty)
            Positioned(
              bottom: 16 + pad.bottom,
              left: 0,
              right: 0,
              child: Center(
                child: _buildSpriteToolbar(
                  c,
                  c.figure.getSegment(c.selectedSegmentId!)!,
                  palette,
                ),
              ),
            ),

        ],
      ),
    );
  }

  Widget _buildSpriteToolbar(EditorController c, Segment seg, AppPalette palette) {
    final activeIdx = c.isAnimateMode
        ? (c.figure.getSegmentImageIndex(seg.id, c.currentTime) ?? seg.activeImageIndex)
        : seg.activeImageIndex;
    final total = seg.imageDataList.length;
    if (total <= 0) return const SizedBox.shrink();

    return OverlayCapsule(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Previous Sprite',
            child: EditorIconButton(
              icon: LucideIcons.chevron_left,
              color: kToolColor,
              disabled: activeIdx <= 0,
              onTap: () {
                if (activeIdx > 0) {
                  c.selectSegmentImage(seg.id, activeIdx - 1);
                  setState(() {});
                }
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 80,
            height: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Sprite ${activeIdx + 1} / $total',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Next Sprite',
            child: EditorIconButton(
              icon: LucideIcons.chevron_right,
              color: kToolColor,
              disabled: activeIdx >= total - 1,
              onTap: () {
                if (activeIdx < total - 1) {
                  c.selectSegmentImage(seg.id, activeIdx + 1);
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openMoreMenu(EditorController c, AppPalette palette) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: palette.backgroundElement,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: palette.backgroundSelected),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12, top: 4),
                      decoration: BoxDecoration(
                        color: palette.textSecondary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "More Options",
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ExpansionTile(
                          initiallyExpanded: true,
                          iconColor: kToolColor,
                          collapsedIconColor: palette.textSecondary,
                          title: Text('Canvas & View', style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.bold)),
                          children: [
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.refresh_cw, size: 16, color: palette.textSecondary),
                              title: Text('Trigger Redraw & Save Layer', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                c.forceUpdate();
                                _showSnack('Redraw & layer triggered');
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.hand, size: 16, color: c.panEnabled ? const Color(0xFF22C55E) : palette.textSecondary),
                              title: Text('Pan Canvas: ${c.panEnabled ? 'On' : 'Off'}', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                c.togglePanEnabled();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(c.showConnectors ? LucideIcons.link : LucideIcons.link_2_off, size: 16, color: palette.textSecondary),
                              title: Text(c.showConnectors ? 'Hide Connectors' : 'Show Connectors', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.toggleConnectors();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.grid_3x3, size: 16, color: palette.textSecondary),
                              title: Text(c.showAxis ? 'Hide Grid Axis' : 'Show Grid Axis', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.toggleAxis();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.grid_3x3, size: 16, color: palette.textSecondary),
                              title: Text(c.snapEnabled ? 'Snap: On' : 'Snap: Off', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.toggleSnap();
                                _showSnack(c.snapEnabled ? 'Snap on' : 'Snap off');
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.plus, size: 16, color: palette.textSecondary),
                              title: Text('Zoom In', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                c.zoomIn();
                                Navigator.of(context).pop();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.minus, size: 16, color: palette.textSecondary),
                              title: Text('Zoom Out', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                c.zoomOut();
                                Navigator.of(context).pop();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.maximize, size: 16, color: palette.textSecondary),
                              title: Text('Reset Zoom', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                c.zoomReset();
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        ),
                        ExpansionTile(
                          initiallyExpanded: false,
                          iconColor: kToolColor,
                          collapsedIconColor: palette.textSecondary,
                          title: Text('Import & Export', style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.bold)),
                          children: [
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.upload, size: 16, color: palette.textSecondary),
                              title: Text('Import SVG', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.importSvg().then((msg) {
                                  if (msg != null) _showSnack(msg);
                                });
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.image, size: 16, color: palette.textSecondary),
                              title: Text('Import SVG as Image', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.importSvgAsImage().then((msg) {
                                  if (msg != null) _showSnack(msg);
                                });
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.user, size: 16, color: palette.textSecondary),
                              title: Text('Import Minecraft Skin', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.controller.importMinecraftSkin(context).then((msg) {
                                  if (msg != null) _showSnack(msg);
                                });
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.file_image, size: 16, color: palette.textSecondary),
                              title: Text('Export GIF', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                _exportGif();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.images, size: 16, color: palette.textSecondary),
                              title: Text('Export PNG Frames', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                _exportPngZip();
                              },
                            ),
                            if (!c.isAnimationProject)
                              ListTile(
                                dense: true,
                                leading: Icon(LucideIcons.film, size: 16, color: palette.textSecondary),
                                title: Text('Export Lottie', style: TextStyle(color: palette.text, fontSize: 13)),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _exportLottie();
                                },
                              ),
                          ],
                        ),
                        ExpansionTile(
                          initiallyExpanded: false,
                          iconColor: kToolColor,
                          collapsedIconColor: palette.textSecondary,
                          title: Text('Preview & Library', style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.bold)),
                          children: [
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.circle_play, size: 16, color: palette.textSecondary),
                              title: Text('Preview', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                _openPreview();
                              },
                            ),
                            ListTile(
                              dense: true,
                              leading: Icon(LucideIcons.bookmark, size: 16, color: palette.textSecondary),
                              title: Text('Poses', style: TextStyle(color: palette.text, fontSize: 13)),
                              onTap: () {
                                Navigator.of(context).pop();
                                _openPoseLibrary();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
