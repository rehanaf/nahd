import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _indexKey = 'id_animate_projects_index';
const _groupsKey = 'id_animate_groups';
const _predefInitKey = 'id_animate_predefs_initialized';
const _profileKey = 'id_animate_profile_name';
const _themeKey = 'id_animate_theme';

String _dataKey(String id) => 'id_animate_project_$id';

enum ProjectType { figure, preset, animation }

class ProjectMeta {
  String id;
  String name;
  ProjectType type;
  int createdAt;
  int updatedAt;
  String? groupId;
  bool? predef;

  ProjectMeta({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.groupId,
    this.predef,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (groupId != null) 'groupId': groupId,
        if (predef != null) 'predef': predef,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> json) => ProjectMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] == 'figure'
            ? ProjectType.figure
            : json['type'] == 'preset'
                ? ProjectType.preset
                : ProjectType.animation,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        groupId: json['groupId'] as String?,
        predef: json['predef'] as bool?,
      );

  ProjectMeta clone() => ProjectMeta.fromJson(toJson());
}

class PredefinedProject {
  ProjectType type;
  String group;
  String name;
  String? figure;
  String? animation;

  PredefinedProject({
    required this.type,
    required this.group,
    required this.name,
    this.figure,
    this.animation,
  });
}

class ProjectGroup {
  String id;
  String name;
  ProjectType type;
  int createdAt;

  ProjectGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'createdAt': createdAt,
      };

  factory ProjectGroup.fromJson(Map<String, dynamic> json) => ProjectGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] == 'figure'
            ? ProjectType.figure
            : json['type'] == 'preset'
                ? ProjectType.preset
                : ProjectType.animation,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

class ProjectData {
  String? figure;
  String? animation;

  ProjectData({this.figure, this.animation});
}

String slugify(String input) {
  final s = input.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  final cleaned = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'untitled' : cleaned;
}

String predefProjectId(ProjectType type, String group, String name) =>
    'predef_${slugify(group)}_${slugify(name)}';

class ProjectStorage {
  ProjectStorage._();

  static List<ProjectMeta> _cachedIndexList = [];
  static List<ProjectGroup> _cachedGroups = [];
  static bool _indexLoaded = false;
  static bool _groupsLoaded = false;

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // -------------------------------------------------------------------------
  // Index
  // -------------------------------------------------------------------------

  static Future<List<ProjectMeta>> loadIndex() async {
    if (_indexLoaded) return _cachedIndexList;
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_indexKey);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          _cachedIndexList = parsed
              .whereType<Map>()
              .map((p) => ProjectMeta.fromJson(p.cast<String, dynamic>()))
              .where((p) => p.id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    _indexLoaded = true;
    return _cachedIndexList;
  }

  static Future<void> persistIndex(List<ProjectMeta> index) async {
    _cachedIndexList = index;
    _indexLoaded = true;
    try {
      final prefs = await _prefs;
      await prefs.setString(
        _indexKey,
        jsonEncode(index.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<List<ProjectMeta>> listProjects([ProjectType? type]) async {
    final index = await loadIndex();
    final sorted = [...index]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return type == null ? sorted : sorted.where((p) => p.type == type).toList();
  }

  static Future<ProjectMeta?> getProject(String id) async {
    final index = await loadIndex();
    for (final p in index) {
      if (p.id == id) return p;
    }
    return null;
  }

  static Future<ProjectMeta> createProject(
    ProjectType type,
    String name, {
    String? groupId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = ProjectMeta(
      id: 'proj_${_randomId()}',
      name: name.trim().isEmpty
          ? (type == ProjectType.animation
              ? 'Untitled Animation'
              : type == ProjectType.preset
                  ? 'Untitled Preset'
                  : 'Untitled Figure')
          : name.trim(),
      type: type,
      createdAt: now,
      updatedAt: now,
      groupId: groupId,
    );
    final index = await loadIndex();
    index.add(meta);
    await persistIndex(index);
    return meta;
  }

  // -------------------------------------------------------------------------
  // Groups
  // -------------------------------------------------------------------------

  static Future<List<ProjectGroup>> loadGroups() async {
    if (_groupsLoaded) return _cachedGroups;
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_groupsKey);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          _cachedGroups = parsed
              .whereType<Map>()
              .map((g) => ProjectGroup.fromJson(g.cast<String, dynamic>()))
              .where((g) => g.id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    _groupsLoaded = true;
    return _cachedGroups;
  }

  static Future<void> persistGroups(List<ProjectGroup> groups) async {
    _cachedGroups = groups;
    _groupsLoaded = true;
    try {
      final prefs = await _prefs;
      await prefs.setString(
        _groupsKey,
        jsonEncode(groups.map((g) => g.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<List<ProjectGroup>> listGroups([ProjectType? type]) async {
    final groups = await loadGroups();
    return type == null
        ? groups
        : groups.where((g) => g.type == type).toList();
  }

  static Future<ProjectGroup> createGroup(
    ProjectType type,
    String name,
  ) async {
    final group = ProjectGroup(
      id: 'grp_${_randomId()}',
      name: name.trim().isEmpty ? 'New Group' : name.trim(),
      type: type,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final groups = await loadGroups();
    groups.add(group);
    await persistGroups(groups);
    return group;
  }

  static Future<void> renameGroup(String id, String name) async {
    final groups = await loadGroups();
    final group = groups.where((g) => g.id == id).toList();
    if (group.isEmpty) return;
    group.first.name = name.trim().isEmpty ? group.first.name : name.trim();
    await persistGroups(groups);
  }

  static Future<void> deleteGroup(String id) async {
    final groups = await loadGroups();
    await persistGroups(groups.where((g) => g.id != id).toList());
    final index = await loadIndex();
    var changed = false;
    for (final p in index) {
      if (p.groupId == id) {
        p.groupId = null;
        changed = true;
      }
    }
    if (changed) await persistIndex(index);
  }

  static Future<void> renameProject(String id, String name) async {
    final index = await loadIndex();
    final meta = index.where((p) => p.id == id).toList();
    if (meta.isEmpty) return;
    meta.first.name = name.trim().isEmpty ? meta.first.name : name.trim();
    meta.first.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await persistIndex(index);
  }

  static Future<ProjectMeta?> copyProject(
    String id, {
    String? name,
    String? groupId,
  }) async {
    final index = await loadIndex();
    final found = index.where((p) => p.id == id).toList();
    if (found.isEmpty) return null;
    final src = found.first;
    final data = await loadProjectData(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = ProjectMeta(
      id: 'proj_${_randomId()}',
      name: (name == null || name.trim().isEmpty)
          ? '${src.name} Copy'
          : name.trim(),
      type: src.type,
      createdAt: now,
      updatedAt: now,
      groupId: groupId ?? src.groupId,
      predef: false,
    );
    index.add(copy);
    await persistIndex(index);
    if (data != null) {
      await saveProjectData(copy.id, data);
    }
    return copy;
  }

  static Future<void> deleteProject(String id) async {
    final index = await loadIndex();
    await persistIndex(index.where((p) => p.id != id).toList());
    try {
      final prefs = await _prefs;
      await prefs.setString(_dataKey(id), '');
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Project data
  // -------------------------------------------------------------------------

  static Future<void> saveProjectData(String id, ProjectData data) async {
    try {
      final prefs = await _prefs;
      await prefs.setString(
        _dataKey(id),
        jsonEncode({'figure': data.figure, 'animation': data.animation}),
      );
    } catch (_) {}
    final index = await loadIndex();
    final meta = index.where((p) => p.id == id).toList();
    if (meta.isNotEmpty) {
      meta.first.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await persistIndex(index);
    }
  }

  static Future<ProjectData?> loadProjectData(String id) async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_dataKey(id));
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          return ProjectData(
            figure: parsed['figure'] is String
                ? parsed['figure'] as String
                : null,
            animation: parsed['animation'] is String
                ? parsed['animation'] as String
                : null,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<ProjectMeta> upsertProjectData(
    ProjectMeta meta,
    ProjectData data,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final index = await loadIndex();
    final existing = index.where((p) => p.id == meta.id).toList();
    if (existing.isNotEmpty) {
      existing.first.name = meta.name;
      existing.first.type = meta.type;
      existing.first.groupId = meta.groupId ?? existing.first.groupId;
      existing.first.predef = meta.predef ?? existing.first.predef;
      existing.first.updatedAt = now;
    } else {
      index.add(ProjectMeta(
        id: meta.id,
        name: meta.name,
        type: meta.type,
        createdAt: meta.createdAt,
        updatedAt: now,
        groupId: meta.groupId,
        predef: meta.predef,
      ));
    }
    await persistIndex(index);
    await saveProjectData(meta.id, data);
    for (final p in index) {
      if (p.id == meta.id) return p;
    }
    return meta;
  }

  // -------------------------------------------------------------------------
  // Predefined projects
  // -------------------------------------------------------------------------

  static Future<int> ensurePredefinedProjects(
    List<PredefinedProject> predefs,
  ) async {
    final prefs = await _prefs;
    var count = 0;
    final index = await loadIndex();
    final ids = {for (final p in index) p.id};
    for (final p in predefs) {
      final id = predefProjectId(p.type, p.group, p.name);
      if (ids.contains(id)) continue;
      await upsertProjectData(
        ProjectMeta(
          id: id,
          name: p.name,
          type: p.type,
          createdAt: 0,
          updatedAt: 0,
          groupId: p.group,
          predef: true,
        ),
        ProjectData(figure: p.figure, animation: p.animation),
      );
      count++;
    }
    if (prefs.getString(_predefInitKey) != '1') {
      await prefs.setString(_predefInitKey, '1');
    }
    return count;
  }

  static Future<int> clearAllData(List<PredefinedProject> predefs) async {
    _indexLoaded = false;
    _groupsLoaded = false;
    _cachedIndexList = [];
    _cachedGroups = [];
    final prefs = await _prefs;
    await prefs.clear();
    return ensurePredefinedProjects(predefs);
  }

  // -------------------------------------------------------------------------
  // Profile & theme
  // -------------------------------------------------------------------------

  static Future<String> getProfileName() async {
    final prefs = await _prefs;
    return prefs.getString(_profileKey) ?? 'Guest';
  }

  static Future<void> setProfileName(String name) async {
    final prefs = await _prefs;
    await prefs.setString(_profileKey, name);
  }

  static Future<String> getThemeMode() async {
    final prefs = await _prefs;
    final mode = prefs.getString(_themeKey);
    if (mode != null &&
        (mode == 'light' || mode == 'dark' || mode == 'device')) {
      return mode;
    }
    return 'device';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(_themeKey, mode);
  }

  static String _randomId() {
    final stamp = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
    final salt = (DateTime.now().millisecond * 7919) & 0xFFFF;
    return '${stamp.toRadixString(36)}${salt.toRadixString(36)}';
  }
}
