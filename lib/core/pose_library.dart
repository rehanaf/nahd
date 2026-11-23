import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/figure.dart';

const _posesKey = 'id_animate_poses';

class PoseTemplate {
  String id;
  String name;
  String figureJson;
  int createdAt;

  PoseTemplate({
    required this.id,
    required this.name,
    required this.figureJson,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'figure': figureJson,
        'createdAt': createdAt,
      };

  factory PoseTemplate.fromJson(Map<String, dynamic> json) {
    final stamp = (json['createdAt'] as num?)?.toInt() ?? 0;
    return PoseTemplate(
      id: json['id'] as String? ?? 'pose_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Pose',
      figureJson: json['figure'] as String? ?? '',
      createdAt: stamp,
    );
  }

  Figure figure() {
    final data = jsonDecode(figureJson);
    if (data is Map<String, dynamic>) return Figure.fromJson(data);
    return Figure.fromJson(const {});
  }
}

/// Pose / template library backed by SharedPreferences. A pose is a saved
/// figure layout (points + segments) that can be saved while posing a rig and
/// re-applied later, or applied to another figure as a quick template.
class PoseLibrary {
  PoseLibrary._();

  static Future<List<PoseTemplate>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_posesKey);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .whereType<Map>()
              .map((p) => PoseTemplate.fromJson(p.cast<String, dynamic>()))
              .where((p) => p.figureJson.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<List<PoseTemplate>> savePose(Figure fig) async {
    final poses = await load();
    poses.add(PoseTemplate(
      id: 'pose_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Pose ${poses.length + 1}',
      figureJson: fig.exportToJson(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _persist(poses);
    return poses;
  }

  static Future<List<PoseTemplate>> rename(String id, String name) async {
    final poses = await load();
    for (final p in poses) {
      if (p.id == id) {
        p.name = name.trim().isEmpty ? p.name : name.trim();
      }
    }
    await _persist(poses);
    return poses;
  }

  static Future<List<PoseTemplate>> delete(String id) async {
    final poses = await load();
    poses.removeWhere((p) => p.id == id);
    await _persist(poses);
    return poses;
  }

  static Future<void> _persist(List<PoseTemplate> poses) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _posesKey,
        jsonEncode(poses.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }
}