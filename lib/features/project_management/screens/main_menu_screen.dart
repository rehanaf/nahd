import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../core/app_version.dart';
import '../../../core/project_io.dart';
import '../../../core/project_storage.dart';
import '../../../core/scene/predefined_projects.dart';
import '../../../core/models/figure.dart';
import '../controllers/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../editor/widgets/figure_preview.dart';
import '../../update/update_dialog.dart';

part 'main_menu_tiles.dart';
part 'main_menu_sheets.dart';

class _GroupRef {
  final String key;
  final String label;
  final String kind; // my | user | predef
  final String? id;
  final int createdAt;

  _GroupRef({
    required this.key,
    required this.label,
    required this.kind,
    this.id,
    this.createdAt = 0,
  });
}

enum _SortOption { type, name, modified }

class _GridItem {
  final _GroupRef? groupRef;
  final ProjectMeta? meta;

  _GridItem.group(this.groupRef) : meta = null;
  _GridItem.project(this.meta) : groupRef = null;

  bool get isGroup => groupRef != null;

  String get label => isGroup ? groupRef!.label : meta!.name;

  int get stamp => isGroup ? groupRef!.createdAt : meta!.updatedAt;
}

class MainMenuScreen extends StatefulWidget {
  final AppController app;
  final void Function(String id, ProjectType type) onOpenProject;
  final ProjectType initialTab;
  final ValueChanged<ProjectType> onTabChanged;

  const MainMenuScreen({
    super.key,
    required this.app,
    required this.onOpenProject,
    required this.initialTab,
    required this.onTabChanged,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  late ProjectType _tab;
  List<ProjectMeta> _projects = [];
  List<ProjectGroup> _groups = [];
  bool _loading = true;
  String? _newTargetGroup;
  _GroupRef? _activeGroup;
  _SortOption _sort = _SortOption.type;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _refresh();
    showUpdateDialogIfAny(context);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await PredefinedProjects.importPredefinedProjects();
    } catch (_) {}
    final list = await ProjectStorage.listProjects(_tab);
    final grps = await ProjectStorage.listGroups(_tab);
    if (mounted) {
      setState(() {
        _projects = list;
        _groups = grps;
        _loading = false;
      });
    }
  }

  void _handleTabChange(ProjectType t) {
    setState(() {
      _tab = t;
      _activeGroup = null;
    });
    widget.onTabChanged(t);
    _refresh();
  }

  List<_GroupRef> get _groupList {
    final predefs = PredefinedProjects.getPredefinedGroups(_tab).map((g) =>
        _GroupRef(key: 'p:$g', label: _capitalize(g), kind: 'predef', id: g));
    final users = _groups.map((g) => _GroupRef(
        key: 'u:${g.id}', label: g.name, kind: 'user', id: g.id, createdAt: g.createdAt));
    return [
      ...predefs,
      ...users,
    ];
  }

  List<ProjectMeta> get _activeProjects {
    if (_activeGroup == null) return [];
    return _projects.where((p) => p.groupId == _activeGroup!.id).toList();
  }

  List<_GridItem> _sortedItems() {
    final items = <_GridItem>[
      for (final ref in _groupList) _GridItem.group(ref),
      for (final p in _projects.where((p) => p.groupId == null))
        _GridItem.project(p),
    ];
    switch (_sort) {
      case _SortOption.type:
        items.sort((a, b) {
          if (a.isGroup != b.isGroup) return a.isGroup ? -1 : 1;
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
        break;
      case _SortOption.name:
        items.sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        break;
      case _SortOption.modified:
        items.sort((a, b) => b.stamp.compareTo(a.stamp));
        break;
    }
    return items;
  }

  Future<void> _handleCreate(String name) async {
    final meta = await ProjectStorage.createProject(_tab, name, groupId: _newTargetGroup);
    if (mounted) widget.onOpenProject(meta.id, meta.type);
  }

  Future<void> _handleDelete(String id) async {
    await ProjectStorage.deleteProject(id);
    _refresh();
  }

  Future<void> _handleExport(ProjectMeta meta) async {
    try {
      await exportProjectZip(meta);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _showCardMenu(ProjectMeta meta) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _MenuSheet(
        options: const [
          _MenuOption('rename', LucideIcons.pencil, 'Rename'),
          _MenuOption('copy', LucideIcons.copy, 'Copy'),
          _MenuOption('export', LucideIcons.archive, 'Export'),
          _MenuOption('delete', LucideIcons.trash, 'Delete', Color(0xFFF87171)),
        ],
        onSelected: (v) => Navigator.of(sheetContext).pop(v),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        _showNameModal(
          title: 'Rename Project',
          placeholder: 'Project Name',
          buttonLabel: 'Rename',
          onSubmit: (v) async {
            await ProjectStorage.renameProject(meta.id, v);
            _refresh();
          },
        );
        break;
      case 'copy':
        await ProjectStorage.copyProject(meta.id);
        _refresh();
        break;
      case 'export':
        _handleExport(meta);
        break;
      case 'delete':
        _handleDelete(meta.id);
        break;
    }
  }

  Future<void> _handleImport() async {
    try {
      final result = await pickAndImportProjectZip();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.imported.isEmpty
                ? 'No project was imported'
                : 'Imported ${result.imported.length} project(s)'),
          ),
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _confirmClearData() async {
    final ok = await _showConfirmSheet(
      title: 'Clear All Data?',
      body:
          'This will delete all your projects and settings, then re-import the predefined scenes.',
      confirmLabel: 'Clear Data',
      danger: true,
    );
    if (ok != true) return;
    try {
      await PredefinedProjects.resetAllProjectData();
      await widget.app.setProfileName('Guest');
      await widget.app.setThemeMode('device');
      setState(() {
        _tab = ProjectType.animation;
        _activeGroup = null;
      });
      _refresh();
    } catch (_) {}
  }

  Future<void> _handleAddGroup(String name) async {
    final g = await ProjectStorage.createGroup(_tab, name);
    await _refresh();
    if (mounted) {
      setState(() {
        _activeGroup = _GroupRef(
            key: 'u:${g.id}',
            label: g.name,
            kind: 'user',
            id: g.id,
            createdAt: g.createdAt);
      });
    }
  }

  Future<void> _confirmDeleteGroup([_GroupRef? ref]) async {
    final g = ref ?? _activeGroup;
    if (g == null || g.kind != 'user' || g.id == null) return;
    final ok = await _showConfirmSheet(
      title: 'Delete Group?',
      body: 'Projects in this group will be moved to My Projects.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true) return;
    await ProjectStorage.deleteGroup(g.id!);
    setState(() => _activeGroup = null);
    _refresh();
  }

  Future<void> _showGroupMenu(_GroupRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _MenuSheet(
        options: const [
          _MenuOption('rename', LucideIcons.pencil, 'Rename'),
          _MenuOption('delete', LucideIcons.trash, 'Delete', Color(0xFFF87171)),
        ],
        onSelected: (v) => Navigator.of(sheetContext).pop(v),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        _showNameModal(
          title: 'Rename Group',
          placeholder: 'Group Name',
          buttonLabel: 'Rename',
          onSubmit: (v) async {
            await ProjectStorage.renameGroup(ref.id!, v);
            _refresh();
          },
        );
        break;
      case 'delete':
        _confirmDeleteGroup(ref);
        break;
    }
  }

  Future<void> _showSortSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _SortSheet(
        current: _sort,
        onSelected: (v) => Navigator.of(sheetContext).pop(v),
      ),
    );
    if (result == null || !mounted) return;
    setState(
        () => _sort = _SortOption.values.firstWhere((e) => e.name == result));
  }

  void _fabPress() {
    _newTargetGroup = _activeGroup?.id;
    _showNameModal(
      title: _tab == ProjectType.animation
          ? 'New Animation'
          : _tab == ProjectType.preset
              ? 'New Animation Preset'
              : 'New Figure',
      placeholder: 'Project Name',
      buttonLabel: 'Create',
      onSubmit: _handleCreate,
    );
  }

  void _addGroupPress() {
    _showNameModal(
      title: 'New Group',
      placeholder: 'Group Name',
      buttonLabel: 'Create',
      onSubmit: _handleAddGroup,
    );
  }

  String get _initials {
    final name = widget.app.profileName.trim();
    return ((name.isEmpty ? 'G' : name).substring(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _appBar(palette),
                _tabs(palette),
                const SizedBox(height: 4),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _activeGroup == null
                          ? _groupsView(palette)
                          : _groupDetailView(palette),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fabPress,
        backgroundColor: const Color(0xFF2563EB),
        child: const Icon(LucideIcons.plus, color: Colors.white, size: 26),
      ),
    );
  }

  Future<void> _openProfile() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ProfileSheet(
        app: widget.app,
        onClearData: () {
          Navigator.of(context).pop();
          _confirmClearData();
        },
      ),
    );
  }

  Widget _appBar(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x26FFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "I'd Animate",
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          InkWell(
            onTap: _handleImport,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(LucideIcons.archive,
                  size: 20, color: palette.text),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openProfile,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF2563EB),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _tabButton(palette, ProjectType.animation, LucideIcons.film, 'Animation'),
          const SizedBox(width: 8),
          _tabButton(palette, ProjectType.preset, LucideIcons.user_check, 'Preset'),
          const SizedBox(width: 8),
          _tabButton(palette, ProjectType.figure, LucideIcons.layout_grid, 'Figure'),
          const Spacer(),
          _sortButton(palette),
          const SizedBox(width: 8),
          _addGroupButton(palette),
        ],
      ),
    );
  }

  Widget _sortButton(AppPalette palette) {
    return InkWell(
      onTap: _showSortSheet,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.backgroundElement,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.backgroundSelected),
        ),
        child: Icon(LucideIcons.arrow_down_up, size: 16, color: palette.text),
      ),
    );
  }

  Widget _addGroupButton(AppPalette palette) {
    return InkWell(
      onTap: _addGroupPress,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: palette.backgroundElement,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.backgroundSelected),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.folder_plus,
                size: 15, color: palette.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Add Group',
              style: TextStyle(
                  color: palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(AppPalette palette, ProjectType type, IconData icon, String label) {
    final active = _tab == type;
    return InkWell(
      onTap: () => _handleTabChange(type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: active ? palette.backgroundElement : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? palette.backgroundSelected : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: active ? palette.text : palette.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? palette.text : palette.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupsView(AppPalette palette) {
    final items = _sortedItems();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bookmark,
                size: 40, color: palette.textSecondary),
            const SizedBox(height: 8),
            Text('Nothing here yet.',
                style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Tap + to create a project.',
                style: TextStyle(color: palette.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }
    return _grid(
      palette,
      items.length,
      (i) => _tileFor(items[i], palette),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
    );
  }

  Widget _tileFor(_GridItem item, AppPalette palette) {
    if (item.isGroup) {
      final ref = item.groupRef!;
      final members = _projects.where((p) => p.groupId == ref.id).toList();
      return _GroupCardTile(
        key: ValueKey(ref.key),
        palette: palette,
        label: ref.label,
        count: members.length,
        members: members,
        onOpen: () => setState(() => _activeGroup = ref),
        onMenu: ref.kind == 'user' ? () => _showGroupMenu(ref) : null,
      );
    }
    final meta = item.meta!;
    return _ProjectCardTile(
      key: ValueKey(meta.id),
      palette: palette,
      meta: meta,
      onOpen: () => widget.onOpenProject(meta.id, meta.type),
      onMenu: () => _showCardMenu(meta),
    );
  }

  Widget _grid(AppPalette palette, int count, Widget Function(int) builder,
      {EdgeInsets padding = EdgeInsets.zero}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - 30) / 4;
        final cellH = cellW * 9 / 16 + 30;
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: cellW / cellH,
          ),
          itemCount: count,
          itemBuilder: (context, i) => builder(i),
        );
      },
    );
  }

  Widget _groupDetailView(AppPalette palette) {
    final g = _activeGroup!;
    final projects = _activeProjects;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x26FFFFFF))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(LucideIcons.chevron_left, size: 22, color: palette.text),
                onPressed: () => setState(() => _activeGroup = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: palette.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${projects.length} ${projects.length == 1 ? 'project' : 'projects'}',
                      style: TextStyle(color: palette.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (g.kind == 'user')
                IconButton(
                  icon: const Icon(LucideIcons.delete, size: 18, color: Color(0xFFF87171)),
                  onPressed: _confirmDeleteGroup,
                ),
            ],
          ),
        ),
        Expanded(
          child: projects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No projects in this group yet.',
                          style: TextStyle(
                              color: palette.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Tap + to create one.',
                          style: TextStyle(color: palette.textSecondary, fontSize: 13)),
                    ],
                  ),
                )
              : _grid(
                  palette,
                  projects.length,
                  (i) => _ProjectCardTile(
                    key: ValueKey(projects[i].id),
                    palette: palette,
                    meta: projects[i],
                    onOpen: () => widget
                        .onOpenProject(projects[i].id, projects[i].type),
                    onMenu: () => _showCardMenu(projects[i]),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Modals
  // -------------------------------------------------------------------------

  Future<void> _showNameModal({
    required String title,
    required String placeholder,
    required String buttonLabel,
    required ValueChanged<String> onSubmit,
  }) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _NameSheet(
          title: title,
          placeholder: placeholder,
          buttonLabel: buttonLabel,
          controller: controller,
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      onSubmit(result);
    }
  }

  Future<bool?> _showConfirmSheet({
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ConfirmSheet(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        danger: danger,
      ),
    );
  }

  String _capitalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }
}

